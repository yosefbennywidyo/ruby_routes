# frozen_string_literal: true

require_relative 'base'
require_relative '../radix_tree'

module RubyRoutes
  module Strategies
    # HybridStrategy: Combines hash-based lookup for static routes with
    # radix tree lookup for dynamic routes.
    #
    # Performance optimization:
    # - Static routes: O(1) hash lookup
    # - Dynamic routes: O(path length) radix tree traversal
    # - Automatic classification based on route pattern
    class HybridStrategy
      include Base

      def initialize
        @static_routes = {}
        @dynamic_routes = RadixTree.new
      end

      # Add a route to the appropriate storage based on whether it's static or dynamic
      #
      # @param route [Route] The route to add
      def add(route)
        if static_route?(route.path)
          @static_routes[route.path] ||= {}
          route.methods.each do |method|
            @static_routes[route.path][method] = route
          end
        else
          # Extract path, methods, and handler from route for RadixTree
          @dynamic_routes.add(route.path, route.methods, route)
        end
      end

      # Find a route for the given path and method
      #
      # @param path [String] The request path
      # @param method [String] The HTTP method
      # @return [Array<Route, Hash>, nil] [route, params] or nil if not found
      def find(path, method)
        if (by_path = @static_routes[path]) && (route = by_path[method.to_s.upcase])
          return [route, RubyRoutes::Constant::EMPTY_HASH]
        end

        # Fall back to dynamic routes
        result = @dynamic_routes.find(path, method)

        # RadixTree returns [nil, {}] when no route found, convert to nil
        return nil if result && result.first.nil?

        result
      end

      private

      # Determine if a route path is static (no parameters)
      #
      # @param path [String] The route path
      # @return [Boolean] true if static, false if dynamic
      def static_route?(path)
        !path.include?(':') && !path.include?('*')
      end
    end
  end
end
