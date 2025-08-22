module RubyRoutes
  module Utility
    class RouteUtility
      def initialize(route_set)
        @route_set = route_set
      end

      # DSL wants to merge scope, RouteSet wants to add a pre‐built Route,
      # so we offer two entry points:
      def define(path, options = {})
        route = Route.new(path, options)
        register(route)
      end

      def register(route)
        @route_set.add_to_collection(route)
        route
      end
    end
  end
end
