require_relative 'segment'

module RubyRoutes
  # Node represents a single node in the radix tree structure.
  # Each node can have static children (exact matches), one dynamic child (parameter capture),
  # and one wildcard child (consumes remaining path segments).
  class Node
    attr_accessor :param_name, :is_endpoint, :dynamic_child, :wildcard_child
    attr_reader :handlers, :static_children

    def initialize
      @is_endpoint = false
      @handlers = {}
      @static_children = {}
      @dynamic_child = nil
      @wildcard_child = nil
      @param_name = nil
    end

    def add_handler(method, handler)
      method_str = normalize_method(method)
      @handlers[method_str] = handler
      @is_endpoint = true
    end

    def get_handler(method)
      @handlers[method]
    end

    # Fast traversal method with minimal allocations and streamlined branching.
    # Matching order: static (most specific) → dynamic → wildcard (least specific)
    # Returns [next_node_or_nil, should_break_bool] where should_break indicates
    # wildcard capture that consumes remaining path segments.
    def traverse_for(segment, index, segments, params)
      # Try static child first (most specific) - O(1) hash lookup
      if @static_children.key?(segment)
        return [@static_children[segment], false]
      # Try dynamic child (parameter capture) - less specific than static
      elsif @dynamic_child
        # Capture parameter if params hash provided and param_name is set
        params[@dynamic_child.param_name] = segment if params && @dynamic_child.param_name
        return [@dynamic_child, false]
      # Try wildcard child (consumes remaining segments) - least specific
      elsif @wildcard_child
        # Capture remaining path segments for wildcard parameter
        if params && @wildcard_child.param_name
          remaining = segments[index..-1]
          params[@wildcard_child.param_name] = remaining.join('/')
        end
        return [@wildcard_child, true] # true signals to stop traversal
      end

      # No match found at this node
      [nil, false]
    end

    private

    # Fast method normalization - converts method to uppercase string
    def normalize_method(method)
      method.to_s.upcase
    end
  end
end
