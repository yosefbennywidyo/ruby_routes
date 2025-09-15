# frozen_string_literal: true

module RubyRoutes
  class Route
    module Matcher
      def match(path, method)
        raise NotImplementedError
      end
    end
  end
end
