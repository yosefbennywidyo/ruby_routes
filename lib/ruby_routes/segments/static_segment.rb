module RubyRoutes
  module Segments
    class StaticSegment < BaseSegment
      def initialize(text)
        @text = text
      end

      def ensure_child(current)
        current.static_children[@text] ||= Node.new
        current.static_children[@text]
      end

      def match(node, text, _idx, _segments, _params)
        [node.static_children[text], false]
      end
    end
  end
end
