require_relative 'segment'

module RubyRoutes
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

    def traverse_for(segment, index, segments, params)
      # Try static child first (most specific)
      if @static_children.key?(segment)
        return [@static_children[segment], false]
      # Try dynamic child (less specific)
      elsif @dynamic_child
        # Capture parameter if params hash provided
        params[@dynamic_child.param_name] = segment if params && @dynamic_child.param_name
        return [@dynamic_child, false]
      # Try wildcard child (least specific)
      elsif @wildcard_child
        # Capture remaining path segments
        if params && @wildcard_child.param_name
          remaining = segments[index..-1]
          params[@wildcard_child.param_name] = remaining.join('/')
        end
        return [@wildcard_child, true] # true signals to stop traversal
      end

      [nil, false]
    end

    private

    def normalize_method(method)
      method.to_s.upcase
    end
  end
end
