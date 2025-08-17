module RubyRoutes
  module Segments
    class WildcardSegment < BaseSegment
      def initialize(text)
        @name = (text[1..-1] || 'splat')
      end

      def ensure_child(current)
        current.wildcard_child ||= Node.new
        current = current.wildcard_child
        current.param_name = @name
        current
      end

      def wildcard?
        true
      end

      def match(node, _text, idx, segments, params)
        return [nil, false] unless node.wildcard_child
        nxt = node.wildcard_child
        params[nxt.param_name.to_s] = segments[idx..-1].join('/') if params
        [nxt, true]
      end
    end
  end
end
