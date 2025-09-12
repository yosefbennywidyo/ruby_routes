# frozen_string_literal: true

require_relative 'base'

module RubyRoutes
  module Strategies
    # HashBasedStrategy
    #
    # A simple hash-based lookup strategy for route matching.
    class HashBasedStrategy
      include Base

      def initialize
        @routes = {}
      end

      def add(route)
        route.methods.each do |method|
          key = "#{method}::#{route.path}"
          @routes[key] = route
        end
      end

      def find(path, http_method)
        key = "#{http_method}::#{path}"
        route = @routes[key]
        return nil unless route

        [route, RubyRoutes::Constant::EMPTY_HASH]
      end
    end
  end
end
