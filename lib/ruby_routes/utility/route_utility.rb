# frozen_string_literal: true

module RubyRoutes
  module Utility
    # RouteUtility
    #
    # Internal DSL helper used by Router / RouteSet to construct and
    # register Route objects. It abstracts the two primary entry points:
    #
    # - #define: Build a new Route from a path + options hash and add it.
    # - #register: Add an already-instantiated Route.
    #
    # This separation lets higher-level DSL code remain concise while
    # keeping RouteSet mutation logic centralized.
    #
    # Thread safety: Not thread-safe; expected to be called during
    # application boot / configuration phase.
    #
    # @api internal
    class RouteUtility
      # @param route_set [RubyRoutes::RouteSet]
      def initialize(route_set)
        @route_set = route_set
      end

      # Build and register a new Route.
      #
      # @param path [String]
      # @param options [Hash] route definition options
      # @return [RubyRoutes::Route]
      #
      # @example
      #   util.define('/users/:id', via: :get, to: 'users#show', as: :user)
      def define(path, options = {})
        route = Route.new(path, options)
        register(route)
      end

      # Register an existing Route instance with the RouteSet.
      #
      # @param route [RubyRoutes::Route]
      # @return [RubyRoutes::Route] the same route (for chaining)
      def register(route)
        @route_set.add_to_collection(route)
        route
      end
    end
  end
end
