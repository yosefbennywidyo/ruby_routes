module RubyRoutes
  module Segments
    class DynamicSegment < BaseSegment
      def initialize(text)
        @name = text[1..-1]
      end

      def ensure_child(current)
        current.dynamic_child ||= Node.new
        current = current.dynamic_child
        current.param_name = @name
        current
      end

      def match(node, text, _idx, _segments, params)
        return [nil, false] unless node.dynamic_child
        nxt = node.dynamic_child
        params[nxt.param_name.to_s] = text if params
        [nxt, false]
      end
    end
  end
end
