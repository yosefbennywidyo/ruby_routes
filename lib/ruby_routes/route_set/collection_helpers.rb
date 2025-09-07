# frozen_string_literal: true

module RubyRoutes
  class RouteSet
    # CollectionHelpers: extracted route collection and enumeration helpers
    # to keep RouteSet implementation small.
    #
    # This module provides methods for managing and querying routes within a
    # `RouteSet`. It includes functionality for adding, finding, clearing, and
    # enumerating routes, as well as managing named routes and caches.
    module CollectionHelpers
      # Add a route object to internal structures.
      #
      # This method adds a route to the internal route collection, updates the
      # matching strategy for fast path/method lookups, and registers the route in the
      # named routes collection if it has a name.
      #
      # @param route [Route] The route to add.
      # @return [Route] The added route.
      def add_to_collection(route)
        return route if @routes.include?(route) # Prevent duplicate insertion

        @named_routes[route.name] = route if route.named?
        @strategy.add(route)
        @routes << route
        route
      end
      alias add_route add_to_collection

      # Register a newly created Route (called from RouteUtility#define).
      #
      # This method initializes the route collection if it is not already set
      # and adds the given route to the collection.
      #
      # @param route [Route] The route to register.
      # @return [Route] The registered route.
      def register(route)
        add_to_collection(route)
      end

      # Find any route (no params) for a method/path.
      #
      # This method searches the matching strategy for a route matching the given HTTP
      # method and path.
      #
      # @param http_method [String, Symbol] The HTTP method (e.g., `:get`, `:post`).
      # @param path [String] The path to match.
      # @return [Route, nil] The matching route, or `nil` if no match is found.
      def find_route(http_method, path)
        route, _params = @strategy.find(path, http_method)
        route
      end

      # Retrieve a named route.
      #
      # This method retrieves a route by its name from the named routes collection.
      # If no route is found, it raises a `RouteNotFound` error.
      #
      # @param name [Symbol] The name of the route.
      # @return [Route] The named route.
      # @raise [RouteNotFound] If no route with the given name is found.
      def find_named_route(name)
        route = @named_routes[name]
        raise RouteNotFound, "No route named '#{name}'" unless route

        route
      end

      # Clear all routes and caches.
      #
      # This method clears the internal route collection, named routes, recognition
      # cache, and matching strategy. It also resets cache hit/miss counters and clears
      # the global request key cache.
      #
      # @return [void]
      def clear_routes_and_caches!
        @cache_mutex.synchronize do
          @routes.clear
          @named_routes.clear
          @recognition_cache.clear
          @small_lru.clear_counters!
          @strategy = @strategy_class.new
          RubyRoutes::Utility::KeyBuilderUtility.clear!
        end
      end

      # Get the number of routes.
      #
      # @return [Integer] The number of routes in the collection.
      def size
        @routes.size
      end

      # Check if the route collection is empty.
      #
      # @return [Boolean] `true` if the collection is empty, `false` otherwise.
      def empty?
        @routes.empty?
      end

      # Enumerate routes.
      #
      # This method yields each route in the collection to the given block. If no
      # block is provided, it returns an enumerator.
      #
      # @yield [route] Yields each route in the collection.
      # @return [Enumerator, self] An enumerator if no block is given, or `self`.
      def each(&block)
        return enum_for(:each) unless block

        @routes.each(&block)
        self
      end

      # Test membership.
      #
      # This method checks if the given route is included in the route collection.
      #
      # @param route [Route] The route to check.
      # @return [Boolean] `true` if the route is in the collection, `false` otherwise.
      def include?(route)
        @routes.include?(route)
      end
    end
  end
end
