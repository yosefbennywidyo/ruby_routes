# frozen_string_literal: true

require_relative 'segment'
require_relative 'utility/path_utility'

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

    include RubyRoutes::Utility::PathUtility

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

    # Traverses from this node using a single path segment.
    # Returns [next_node_or_nil, stop_traversal(Boolean)].
    #
    # Optimized + simplified (cyclomatic / perceived complexity, length).
    def traverse_for(segment, index, segments, params)
      return [@static_children[segment], false] if @static_children[segment]

      if @dynamic_child
        capture_dynamic_param(params, @dynamic_child, segment)
        return [@dynamic_child, false]
      end

      if @wildcard_child
        capture_wildcard_param(params, @wildcard_child, segments, index)
        return [@wildcard_child, true]
      end

      RubyRoutes::Constant::NO_TRAVERSAL_RESULT
    end

    private

    # Captures a dynamic parameter value into the params hash if applicable.
    #
    # @param params [Hash, nil] the parameters hash to update
    # @param dyn_node [Node] the dynamic child node
    # @param value [String] the segment value to capture
    def capture_dynamic_param(params, dyn_node, value)
      return unless params && dyn_node.param_name

      params[dyn_node.param_name] = value
    end

    # Captures a wildcard parameter value into the params hash if applicable.
    #
    # @param params [Hash, nil] the parameters hash to update
    # @param wc_node [Node] the wildcard child node
    # @param segments [Array<String>] the full path segments
    # @param index [Integer] the current segment index
    def capture_wildcard_param(params, wc_node, segments, index)
      return unless params && wc_node.param_name

      params[wc_node.param_name] = segments[index..].join('/')
    end
  end
end
