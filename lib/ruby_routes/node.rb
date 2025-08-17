require_relative 'segment'

module RubyRoutes
  class Node
    attr_accessor :static_children, :dynamic_child, :wildcard_child,
                  :handlers, :param_name, :is_endpoint

    def initialize
      @static_children = {}
      @dynamic_child = nil
      @wildcard_child = nil
      @handlers = {}
      @param_name = nil
      @is_endpoint = false
    end

    # Traverse for a single segment using the matcher registry.
    # Returns [next_node_or_nil, should_break_bool] or [nil, false] if no match.
    def traverse_for(segment, index, segments, params)
      # Prefer static children first (exact match).
      if @static_children.key?(segment)
        return [@static_children[segment], false]
      end

      # Then dynamic param child (single segment)
      if @dynamic_child
        next_node = @dynamic_child
        if params
          params[next_node.param_name.to_s] = segment
        end
        return [next_node, false]
      end

      # Then wildcard child (consume remainder)
      if @wildcard_child
        next_node = @wildcard_child
        if params
          params[next_node.param_name.to_s] = segments[index..-1].join('/')
        end
        return [next_node, true]
      end

      # No match at this node
      [nil, false]
    end

    def add_handler(method, handler)
      @handlers[method.to_s] = handler
      @is_endpoint = true
    end

    def get_handler(method)
      @handlers[method.to_s]
    end
  end
end
