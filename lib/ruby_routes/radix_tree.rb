# frozen_string_literal: true

require_relative 'segment'
require_relative 'utility/path_utility'
require_relative 'node'

module RubyRoutes
  # RadixTree
  #
  # Compact routing trie (radix‑like) supporting:
  # - Static segments: /users
  # - Dynamic params:  /users/:id
  # - Wildcards (splat): /assets/*path
  #
  # Features:
  # - Longest prefix match (keeps deepest successful endpoint while traversing).
  # - Param + wildcard capture merged directly into provided params hash.
  # - Small LRU‑style split cache (string → segments array) to reduce split cost.
  #
  # Thread safety: not thread‑safe (constructed during boot, read during requests).
  #
  # @api internal
  class RadixTree
    include RubyRoutes::Utility::PathUtility
    include RubyRoutes::Utility::MethodUtility

    class << self
      # Convenience factory: RadixTree.new(path, opts) returns a Route.
      # Retained for backwards DSL compatibility.
      #
      # @param args [Array]
      # @return [RubyRoutes::Route, RadixTree]
      def new(*args, &block)
        if args.any?
          RubyRoutes::Route.new(*args, &block)
        else
          super()
        end
      end
    end

    # Initialize an empty tree with segment split cache.
    def initialize
      @root              = Node.new
      @split_cache       = {}
      @split_cache_order = []
      @split_cache_max   = 2048
      @empty_segments    = [].freeze
    end

    # Add a route to the tree.
    #
    # @param path [String]
    # @param methods [Array<String,Symbol>]
    # @param handler [Object] Route (or callable)
    # @return [Object] handler
    def add(path, methods, handler)
      normalized_path = normalize_path(path)
      upcased_methods = methods.map { |method| normalize_http_method(method) }
      insert_route(normalized_path, upcased_methods, handler)
      handler
    end

    # Insert a route by decomposing its path into nodes.
    #
    # @param path_str [String]
    # @param methods [Array<String>]
    # @param handler [Object]
    # @return [Object] handler
    def insert_route(path_str, methods, handler)
      return handler if path_str.nil? || path_str.empty?

      path_segments = split_path(path_str)
      node = @root
      path_segments.each do |segment_text|
        if segment_text.start_with?(':')
          param_name = segment_text[1..-1]
          unless node.dynamic_child
            node.dynamic_child = Node.new
            node.dynamic_child.param_name = param_name
          end
          node = node.dynamic_child
        elsif segment_text.start_with?('*')
          param_name = segment_text[1..-1]
          unless node.wildcard_child
            node.wildcard_child = Node.new
            node.wildcard_child.param_name = param_name
          end
          node = node.wildcard_child
          break
        else
          lit = segment_text.freeze
          node.static_children[lit] ||= Node.new
          node = node.static_children[lit]
        end
      end

      node.is_endpoint = true
      Array(methods).each { |http_method| node.handlers[http_method.to_s.upcase] = handler }
      handler
    end

    # Find a route for given path + method.
    #
    # Traversal collects the deepest valid endpoint (best_match_node) so
    # partial overlaps still resolve appropriately when a later branch fails.
    #
    # @param path [String]
    # @param method [String,Symbol]
    # @param params_out [Hash] optional mutable hash for captures
    # @return [Array<(Object, Hash)>] [handler_or_nil, params_hash]
    def find(path, method, params_out = {})
      request_path      = path.to_s
      normalized_method = method.to_s.upcase

      if request_path.empty? || request_path == '/'
        return @root.is_endpoint && @root.handlers[normalized_method] ?
          [@root.handlers[normalized_method], params_out || {}] :
          [nil, params_out || {}]
      end

      path_segments = split_path_cached(request_path)
      return [nil, params_out || {}] if path_segments.empty?

      extracted_params  = params_out || {}
      best_match_node   = nil
      best_match_params = nil
      node = @root

      path_segments.each_with_index do |segment_value, index|
        next_node, stop_traversal = node.traverse_for(segment_value, index, path_segments, extracted_params)

        unless next_node
          if best_match_node
            handler = best_match_node.handlers[normalized_method]
            if handler.respond_to?(:constraints)
              cons = handler.constraints
              if cons && !cons.empty?
                return check_constraints(handler, best_match_params) ? [handler, best_match_params] : [nil, extracted_params]
              end
            end
            return [handler, best_match_params]
          end
          return [nil, extracted_params]
        end

        node = next_node
        if node.is_endpoint && node.handlers[normalized_method]
          best_match_node   = node
          best_match_params = extracted_params.dup
        end
        break if stop_traversal
      end

      if node.is_endpoint && node.handlers[normalized_method]
        handler = node.handlers[normalized_method]
        if handler.respond_to?(:constraints)
          cons = handler.constraints
          if cons && !cons.empty?
            if check_constraints(handler, extracted_params)
              return [handler, extracted_params]
            else
              if best_match_node && best_match_node != node
                fallback = best_match_node.handlers[normalized_method]
                return [fallback, best_match_params] if fallback
              end
              return [nil, extracted_params]
            end
          end
        end
        return [handler, extracted_params]
      end

      if best_match_node
        handler = best_match_node.handlers[normalized_method]
        if handler.respond_to?(:constraints)
          cons = handler.constraints
          if cons && !cons.empty?
            return check_constraints(handler, best_match_params) ? [handler, best_match_params] : [nil, extracted_params]
          end
        end
        return [handler, best_match_params]
      end

      [nil, extracted_params]
    end

    private

    # Cached path splitting with simple LRU eviction (front shift).
    #
    # @param path [String]
    # @return [Array<String>]
    def split_path_cached(path)
      return @empty_segments if path == '/'

      if @split_cache.key?(path)
        @split_cache_order.delete(path)
        @split_cache_order << path
        return @split_cache[path]
      end

      segments = split_path(path)
      if @split_cache.size >= @split_cache_max
        evicted = @split_cache_order.shift
        @split_cache.delete(evicted)
      end
      @split_cache[path] = segments
      @split_cache_order << path
      segments
    end

    # Constraint evaluation (subset of full validation).
    #
    # @param handler [Object]
    # @param params [Hash]
    # @return [Boolean]
    def check_constraints(handler, params)
      return true unless handler.respond_to?(:constraints)
      constraints = handler.constraints
      return true unless constraints && !constraints.empty?

      constraints.each do |param_name, rule|
        key = param_name.to_s
        value = params[key]
        next unless value
        case rule
        when Regexp
          return false unless rule.match?(value.to_s)
        when :int
          return false unless value.to_s.match?(/\A\d+\z/)
        when :uuid
          return false unless value.to_s.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
        when Hash
          if rule[:range].is_a?(Range)
            numeric = value.to_i
            return false unless rule[:range].include?(numeric)
          end
        end
      end
      true
    end
  end
end
