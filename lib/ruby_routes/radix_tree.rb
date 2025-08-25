# frozen_string_literal: true

require_relative 'route/small_lru'
require_relative 'segment'
require_relative 'utility/path_utility'
require_relative 'utility/method_utility'
require_relative 'node'

module RubyRoutes
  # RadixTree
  #
  # Compact routing trie supporting:
  # - Static segments  (/users)
  # - Dynamic segments (/users/:id)
  # - Wildcard splat   (/assets/*path)
  #
  # Design / Behavior:
  # - Traversal keeps track of the deepest valid endpoint encountered
  #   (best_match_node) so that if a later branch fails, we can still
  #   return a shorter matching route.
  # - Dynamic and wildcard captures are written directly into the caller
  #   supplied params Hash (or a fresh one) to avoid intermediate objects.
  # - A very small manual LRU (Hash + order Array) caches the result of
  #   splitting raw paths into their segment arrays.
  #
  # Matching Precedence:
  #   static > dynamic > wildcard
  #
  # Thread Safety:
  # - Not thread‑safe for mutation (intended for boot‑time construction).
  #   Safe for concurrent reads after routes are added.
  #
  # @api internal
  class RadixTree
    include RubyRoutes::Utility::PathUtility
    include RubyRoutes::Utility::MethodUtility

    class << self
      # Backwards DSL convenience: RadixTree.new(args) → Route
      def new(*args, &block)
        if args.any?
          RubyRoutes::Route.new(*args, &block)
        else
          super()
        end
      end
    end

    # Initialize empty tree and split cache.
    def initialize
      @root_node          = Node.new
      @split_cache        = RubyRoutes::Route::SmallLru.new(2048)
      @split_cache_max    = 2048
      @split_cache_order  = []
      @empty_segment_list = [].freeze
    end

    # Add a route to the tree.
    #
    # @param raw_path [String]
    # @param http_methods [Array<String,Symbol>]
    # @param route_handler [Object]
    # @return [Object] route_handler
    def add(raw_path, http_methods, route_handler)
      normalized_path    = normalize_path(raw_path)
      normalized_methods = http_methods.map { |m| normalize_http_method(m) }
      insert_route(normalized_path, normalized_methods, route_handler)
      route_handler
    end

    # Insert (compile) a route path into the tree structure.
    #
    # @param path_string [String]
    # @param http_methods [Array<String>]
    # @param route_handler [Object]
    # @return [Object]
    def insert_route(path_string, http_methods, route_handler)
      return route_handler if path_string.nil? || path_string.empty?

      segment_tokens = split_path(path_string)
      current_node   = @root_node

      segment_tokens.each do |segment_token|
        if segment_token.start_with?(':')
          parameter_name = segment_token[1..-1]
          unless current_node.dynamic_child
            current_node.dynamic_child = Node.new
            current_node.dynamic_child.param_name = parameter_name
          end
          current_node = current_node.dynamic_child
        elsif segment_token.start_with?('*')
          parameter_name = segment_token[1..-1]
          unless current_node.wildcard_child
            current_node.wildcard_child = Node.new
            current_node.wildcard_child.param_name = parameter_name
          end
          current_node = current_node.wildcard_child
          break # wildcard consumes remaining path
        else
          literal_segment = segment_token.freeze
          current_node.static_children[literal_segment] ||= Node.new
          current_node = current_node.static_children[literal_segment]
        end
      end

      current_node.is_endpoint = true
      http_methods.each { |method_str| current_node.handlers[method_str] = route_handler }
      route_handler
    end

    # Locate a handler for (path, method).
    #
    # @param request_path_input [String]
    # @param request_method_input [String,Symbol]
    # @param params_out [Hash] optional params Hash to populate
    # @return [Array<(Object, Hash)>] [handler_or_nil, params_hash]
    def find(request_path_input, request_method_input, params_out = {})
      request_path      = request_path_input.to_s
      normalized_method = normalize_http_method(request_method_input)

      if request_path.empty? || request_path == '/'
        return @root_node.is_endpoint && @root_node.handlers[normalized_method] ?
          [@root_node.handlers[normalized_method], params_out || {}] :
          [nil, params_out || {}]
      end

      segment_tokens = split_path_cached(request_path)
      return [nil, params_out || {}] if segment_tokens.empty?

      captured_params     = params_out || {}
      best_match_node     = nil
      best_match_params   = nil
      current_node        = @root_node

      segment_tokens.each_with_index do |segment_text, segment_index|
        next_node, stop_traversal = current_node.traverse_for(
          segment_text,
          segment_index,
          segment_tokens,
          captured_params
        )

        unless next_node
          if best_match_node
            handler = best_match_node.handlers[normalized_method]
            return check_constraints(handler, best_match_params) ? [handler, best_match_params] : [nil, captured_params ]
          end
          return [nil, captured_params]
        end

        current_node = next_node

        if current_node.is_endpoint && current_node.handlers[normalized_method]
          best_match_node   = current_node
          best_match_params = captured_params
        end

        break if stop_traversal
      end

      # Primary candidate: current node
      if current_node.is_endpoint && (handler = current_node.handlers[normalized_method])
        if check_constraints(handler, captured_params)
          return [handler, captured_params]
        elsif best_match_node && best_match_node != current_node
          # Fallback to earlier (shorter) match if its constraints pass
          fallback = best_match_node.handlers[normalized_method]
          return [fallback, best_match_params] if fallback && check_constraints(fallback, best_match_params)
          return [nil, captured_params]
        else
          return [nil, captured_params]
        end
      end

      # Longest prefix fallback
      if best_match_node
        handler = best_match_node.handlers[normalized_method]
        return [handler, best_match_params] if handler && check_constraints(handler, best_match_params)
      end

      [nil, captured_params]
    end

    private

    # Split path with small manual LRU cache.
    #
    # @param raw_path [String]
    # @return [Array<String>]
    def split_path_cached(raw_path)
      return @empty_segment_list if raw_path == '/'

      cached = @split_cache.get(raw_path)
      return cached if cached

      segments = split_path(raw_path)
      @split_cache.set(raw_path, segments)
      segments
    end

    # Evaluate constraint rules for a candidate route.
    #
    # @param route_handler [Object]
    # @param captured_params [Hash]
    # @return [Boolean]
    def check_constraints(route_handler, captured_params)
      return true unless route_handler.respond_to?(:validate_constraints_fast!)
      # Use a duplicate to avoid unintended mutation by validators.
      route_handler.validate_constraints_fast!(captured_params)
      true
    rescue RubyRoutes::ConstraintViolation
      false
    end
  end
end
