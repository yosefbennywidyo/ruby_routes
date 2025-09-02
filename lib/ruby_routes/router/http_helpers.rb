# frozen_string_literal: true

require_relative 'build_helpers'
require_relative 'scope_helpers'
require_relative 'resource_helpers'

module RubyRoutes
  class Router
    # HttpHelpers
    #
    # DSL methods exposing HTTP verb helpers (`get`, `post`, `put`, `patch`, `delete`, `match`)
    # and small wiring helpers. Resource- and nested-related logic is delegated
    # to `Router::ResourceHelpers` to keep this module focused.
    #
    # This module provides methods to define routes for various HTTP verbs, apply
    # scopes, and manage route definitions. It also includes helper methods for
    # defining singular resource routes.
    module HttpHelpers
      include RubyRoutes::Router::BuildHelpers
      include RubyRoutes::Router::ScopeHelpers
      include RubyRoutes::Router::ResourceHelpers

      # ---- HTTP Verb Helpers -------------------------------------------------

      # Define a GET route.
      #
      # @param path [String] The path for the route.
      # @param options [Hash] The options for the route.
      # @return [Router] Returns self for chaining.
      def get(path, options = {})
        add_route(path, build_route_options(options, :get))
        self
      end

      # Define a POST route.
      #
      # @param path [String] The path for the route.
      # @param options [Hash] The options for the route.
      # @return [Router] Returns self for chaining.
      def post(path, options = {})
        add_route(path, build_route_options(options, :post))
        self
      end

      # Define a PUT route.
      #
      # @param path [String] The path for the route.
      # @param options [Hash] The options for the route.
      # @return [Router] Returns self for chaining.
      def put(path, options = {})
        add_route(path, build_route_options(options, :put))
        self
      end

      # Define a PATCH route.
      #
      # @param path [String] The path for the route.
      # @param options [Hash] The options for the route.
      # @return [Router] Returns self for chaining.
      def patch(path, options = {})
        add_route(path, build_route_options(options, :patch))
        self
      end

      # Define a DELETE route.
      #
      # @param path [String] The path for the route.
      # @param options [Hash] The options for the route.
      # @return [Router] Returns self for chaining.
      def delete(path, options = {})
        add_route(path, build_route_options(options, :delete))
        self
      end

      # Define a route for multiple HTTP methods.
      #
      # @param path [String] The path for the route.
      # @param options [Hash] The options for the route.
      #   - `:via` [Array<Symbol>] The HTTP methods to allow (e.g., `[:get, :post]`).
      # @raise [ArgumentError] If `:via` is not provided or is empty.
      # @return [Router] Returns self for chaining.
      def match(path, options = {})
        via = options[:via]
        raise ArgumentError, 'match requires :via (e.g., via: [:get, :post])' if via.nil? || Array(via).empty?

        add_route(path, options)
        self
      end

      private

      # Add a route to the router.
      #
      # This method applies the current scope to the route and defines it using
      # the route utilities.
      #
      # @param path [String] The path for the route.
      # @param options [Hash] The options for the route.
      # @return [void]
      def add_route(path, options = {})
        ensure_unfrozen!
        scoped = apply_scope(path, options)
        @route_utils.define(scoped[:path], scoped)
      end

      # Ensure the router is not frozen.
      #
      # @raise [RuntimeError] If the router is frozen.
      # @return [void]
      def ensure_unfrozen!
        raise 'Router finalized (immutable)' if @frozen || frozen?
      end

      # Define routes for a singular resource.
      #
      # This method defines routes for a singular resource (e.g., `/profile`),
      # including standard RESTful actions like `show`, `new`, `create`, `edit`,
      # `update`, and `destroy`.
      #
      # @param singular [String] The name of the singular resource.
      # @param controller [String] The name of the controller handling the resource.
      # @param options [Hash] Additional options for the routes.
      # @return [void]
      def define_singular_routes(singular, controller, options)
        get    "/#{singular}",       options.merge(to: "#{controller}#show")
        get    "/#{singular}/new",   options.merge(to: "#{controller}#new")
        post   "/#{singular}",       options.merge(to: "#{controller}#create")
        get    "/#{singular}/edit",  options.merge(to: "#{controller}#edit")
        put    "/#{singular}",       options.merge(to: "#{controller}#update")
        patch  "/#{singular}",       options.merge(to: "#{controller}#update")
        delete "/#{singular}",       options.merge(to: "#{controller}#destroy")
      end
    end
  end
end
