module RubyRoutes
  module Segments
    class BaseSegment
      def initialize(text = nil)
        @text = text.to_s if text
      end

      def wildcard?
        false
      end

      def ensure_child(current)
        raise NotImplementedError, "#{self.class}#ensure_child must be implemented"
      end

      def match(_node, _text, _idx, _segments, _params)
        raise NotImplementedError, "#{self.class}#match must be implemented"
      end
    end
  end
end
