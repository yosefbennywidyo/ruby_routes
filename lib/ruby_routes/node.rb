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
      @handlers[method]
    end

    # Traverse to the most specific child for a single path segment.
    #
    # Order:
    # 1. static child (exact match)
    # 2. dynamic child (capture single segment)
    # 3. wildcard child (capture remaining segments; halts traversal)
    #
    # @param segment [String] current path component
    # @param index [Integer] index of this segment in full list
    # @param segments [Array<String>] full path segments
    # @param params [Hash, nil] hash to populate with captures
    # @return [Array<(Node,nil),(Boolean)>] [next_node_or_nil, stop_traversal]
    def traverse_for(segment, index, segments, params)
      if @static_children.key?(segment)
        return [@static_children[segment], false]
      elsif @dynamic_child
        params[@dynamic_child.param_name] = segment if params && @dynamic_child.param_name
        return [@dynamic_child, false]
      elsif @wildcard_child
        if params && @wildcard_child.param_name
          remaining_segments = segments[index..-1]
          params[@wildcard_child.param_name] = remaining_segments.join('/')
        end
        return [@wildcard_child, true]
      end
      [nil, false]
    end

    private

    # Normalize HTTP method to uppercase String (fast path).
    #
    # @param method [String, Symbol]
    # @return [String]
    def normalize_method(method)
      method.to_s.upcase
    end
  end
end
