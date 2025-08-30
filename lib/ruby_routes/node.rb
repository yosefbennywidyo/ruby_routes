# frozen_string_literal: true

require_relative 'segment'

module RubyRoutes
  # Node
  #
  # A single vertex in the routing radix tree.
  #
  # Structure:
  # - static_children: Hash<String, Node> exact literal matches.
  # - dynamic_child:   Node (":param") matches any single segment, captures value.
  # - wildcard_child:  Node ("*splat") matches remaining segments (greedy).
  #
  # Handlers:
  # - @handlers maps canonical HTTP method strings (e.g. "GET") to Route objects (or callable handlers).
  # - @is_endpoint marks that at least one handler is attached (terminal path).
  #
  # Matching precedence (most → least specific):
  #   static → dynamic → wildcard
  #
  # Thread safety: not thread-safe (build during boot).
  #
  # @api internal
  class Node
    attr_accessor :param_name, :is_endpoint, :dynamic_child, :wildcard_child
    attr_reader :handlers, :static_children

    def initialize
      @is_endpoint     = false
      @handlers        = {}
      @static_children = {}
      @dynamic_child   = nil
      @wildcard_child  = nil
      @param_name      = nil
    end

    # Register a handler under an HTTP method.
    #
    # @param method [String, Symbol]
    # @param handler [Object] route or callable
    # @return [Object] handler
    def add_handler(method, handler)
      method_str = normalize_method(method)
      @handlers[method_str] = handler
      @is_endpoint = true
      handler
    end

    # Fetch a handler for a method.
    #
    # @param method [String, Symbol]
    # @return [Object, nil]
    def get_handler(method)
      @handlers[normalize_method(method)]
    end

    NO_TRAVERSAL_RESULT = [nil, false].freeze

    # Traverses from this node using a single path segment.
    # Returns [next_node_or_nil, stop_traversal(Boolean)].
    #
    # Optimized + simplified to satisfy RuboCop metrics (cyclomatic / perceived complexity, length).
    def traverse_for(segment, index, segments, params)
      if (child = @static_children[segment])
        return [child, false]
      end

      if (dyn = @dynamic_child)
        capture_dynamic_param(params, dyn, segment)
        return [dyn, false]
      end

      if (wc = @wildcard_child)
        capture_wildcard_param(params, wc, segments, index)
        return [wc, true]
      end

      NO_TRAVERSAL_RESULT
    end

    private

    def capture_dynamic_param(params, dyn_node, value)
      return unless params && dyn_node.param_name
      params[dyn_node.param_name] = value
    end

    def capture_wildcard_param(params, wc_node, segments, index)
      return unless params && wc_node.param_name
      params[wc_node.param_name] = segments[index..].join('/')
    end

    # Normalize HTTP method to uppercase String (fast path).
    #
    # @param method [String, Symbol]
    # @return [String]
    def normalize_method(method)
      method.to_s.upcase
    end
  end
end
