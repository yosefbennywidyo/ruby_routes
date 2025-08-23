# frozen_string_literal: true

require_relative 'ruby_routes/version'
require_relative 'ruby_routes/constant'
require_relative 'ruby_routes/string_extensions'
require_relative 'ruby_routes/route'
require_relative 'ruby_routes/route_set'
require_relative 'ruby_routes/url_helpers'
require_relative 'ruby_routes/router'
require_relative 'ruby_routes/radix_tree'
require_relative 'ruby_routes/node'
require_relative 'ruby_routes/router/builder'

# RubyRoutes
#
# RubyRoutes: High-performance, thread-safe routing DSL for Ruby applications.
# Provides Rails-like route definitions, RESTful resources, constraints, path generation, and advanced caching.
#
# See README.md for usage, API, migration, and security notes.
#
# Responsibilities:
# - Autoload and require all core components:
#   - version, string_extensions, route, route_set, url_helpers, router, radix_tree, node, router/builder
# - Provide `.draw` helper to build a finalized, immutable router.
# - Expose version and convenience APIs for router creation.
#
# Thread-safety & Immutability:
# - All loaded structures (constants, frozen route sets, caches) are safe for concurrent use.
# - Modifications (route additions) are not thread-safe; always use `RubyRoutes.draw` in an initializer or at boot.
# - After build/finalize, all internals are deeply frozen for safety.
#
# Security & Migration:
# - Proc constraints are deprecated; see `MIGRATION_GUIDE.md` for secure alternatives.
# - `RouteSet#match` returns frozen params; callers must `.dup` if mutation is needed.
# - See `SECURITY_FIXES.md` for details on security improvements.
#
# Performance:
# - Optimized for low memory usage, high cache hit rates, and zero memory leaks.
# - See `README.md` for benchmark results.
#
# @api public
module RubyRoutes
  # Base error class for RubyRoutes-specific exceptions.
  class Error < StandardError; end

  # Raised when a route cannot be found.
  class RouteNotFound < Error; end

  # Raised when a route is invalid.
  class InvalidRoute < Error; end

  # Raised when a constraint validation fails.
  class ConstraintViolation < Error; end

  # Create a new router instance.
  #
  # @example Define routes using a block
  #   router = RubyRoutes.new do
  #     get '/health', to: 'system#health'
  #     resources :users
  #   end
  #
  # @param block [Proc] The block defining the routes.
  # @return [RubyRoutes::Router] A new router instance.
  def self.new(&block)
    RubyRoutes::Router.new(&block)
  end

  # Define the routes using a block and return a finalized router.
  #
  # @example Define and finalize routes
  #   router = RubyRoutes.draw do
  #     get '/health', to: 'system#health'
  #     resources :users
  #   end
  #
  # @param block [Proc] The block defining the routes.
  # @return [RubyRoutes::Router] A finalized router instance.
  def self.draw(&block)
    RubyRoutes::Router.build(&block)
  end
end
