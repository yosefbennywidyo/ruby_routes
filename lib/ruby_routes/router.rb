# frozen_string_literal: true

require_relative 'utility/inflector_utility'
require_relative 'utility/route_utility'
require_relative 'router/http_helpers'
require_relative 'constant'
require_relative 'route_set'
module RubyRoutes
  # RubyRoutes::Router
  #
  # Public DSL entrypoint for defining application routes.
  #
  # Usage:
  #   router = RubyRoutes::Router.new do
  #     get '/health', to: 'system#health'
  #     resources :users
  #     namespace :admin do
  #       resources :posts
  #     end
  #   end
  #
  # Thread Safety:
  #   Build routes at boot. Mutating after multiple threads start serving
  #   requests is not supported.
  #
  # Responsibilities:
  # - Provide Rails‑inspired DSL (get/post/put/patch/delete/match/root).
  # - Define RESTful collections via `#resources` and singular via `#resource`.
  # - Support scoping (namespace / scope / constraints / defaults).
  # - Allow reusable blocks via concerns (`#concern` / `#concerns`).
  # - Mount external Rack apps (`#mount`).
  # - Delegate route object creation & storage to `RouteSet` / `RouteUtility`.
  #
  # Design Notes:
  # - Scope stack is an array of shallow hashes (path/module/constraints/defaults).
  # - Scopes are applied inner-first (reverse_each). For options (constraints/defaults),
  #   inner values should override outer ones.
  # - Options hashes passed by users are duplicated only when necessary
  #   (see `build_route_options`) to reduce allocation churn.
  #
  # Public API Surface (Stable):
  # - `#initialize` (block form)
  # - HTTP verb helpers (`get/post/put/patch/delete/match`)
  # - `#root`
  # - `#resources` / `#resource`
  # - `#namespace` / `#scope` / `#constraints` / `#defaults`
  # - `#concern` / `#concerns`
  # - `#mount`
  #
  # Internal / Subject to Change:
  # - `#add_route`
  # - `#apply_scope`
  # - `#build_route_options`
  # - `#push_scope`
  #
  # @api public
  class Router
    VERBS_ALL = RubyRoutes::Constant::VERBS_ALL

    attr_reader :route_set

    include RubyRoutes::Router::HttpHelpers

    # Initialize the router.
    #
    # @param definition_block [Proc] The block to define routes.
    def initialize(&definition_block)
      @route_set   = RouteSet.new
      @route_utils = RubyRoutes::Utility::RouteUtility.new(@route_set)
      @scope_stack = []
      @concerns    = {}
      instance_eval(&definition_block) if definition_block
    end

    # Build a finalized router.
    #
    # @param definition_block [Proc] The block to define routes.
    # @return [Router] The finalized router.
    def self.build(&definition_block)
      new(&definition_block).finalize!
    end

    # Finalize router for DSL immutability.
    #
    # @return [Router] self.
    def finalize!
      return self if @frozen

      @frozen = true
      @scope_stack.freeze
      @concerns.freeze
      self
    end

    # Check if the router is frozen.
    #
    # @return [Boolean] `true` if the router is frozen, `false` otherwise.
    def frozen?
      !!@frozen
    end

    # Define a root route.
    #
    # @param options [Hash] The options for the root route.
    # @return [Router] self.
    def root(options = {})
      add_route('/', build_route_options(options, :get))
      self
    end

    # ---- RESTful Resources -------------------------------------------------

    # Define RESTful resources.
    #
    # @param resource_name [Symbol, String] The resource name.
    # @param options [Hash] The options for the resource.
    # @param nested_block [Proc] The block for nested routes.
    # @return [Router] self.
    def resources(resource_name, options = {}, &nested_block)
      define_resource_routes(resource_name, options, &nested_block)
      self
    end

    # Define a singular resource.
    #
    # @param resource_name [Symbol, String] The resource name.
    # @param options [Hash] The options for the resource.
    # @return [Router] self.
    def resource(resource_name, options = {})
      singular   = RubyRoutes::Utility::InflectorUtility.singularize(resource_name.to_s)
      controller = options[:controller] || singular
      define_singular_routes(singular, controller, options)
    end

    # ---- Scoping & Namespaces ----------------------------------------------

    # Define a namespace.
    #
    # @param namespace_name [Symbol, String] The namespace name.
    # @param options [Hash] The options for the namespace.
    # @param block [Proc] The block for nested routes.
    # @return [Router] self.
    def namespace(namespace_name, options = {}, &block)
      push_scope({ path: "/#{namespace_name}", module: namespace_name }.merge(options)) do
        instance_eval(&block) if block
      end
    end

    # Define a scope.
    #
    # @param options_or_path [Hash, String] The options or path for the scope.
    # @param block [Proc] The block for nested routes.
    # @return [Router] self.
    def scope(options_or_path = {}, &block)
      scope_entry = options_or_path.is_a?(String) ? { path: options_or_path } : options_or_path
      push_scope(scope_entry) { instance_eval(&block) if block }
    end

    # Define constraints.
    #
    # @param constraints_hash [Hash] The constraints for the scope.
    # @param block [Proc] The block for nested routes.
    # @return [Router] self.
    def constraints(constraints_hash = {}, &block)
      push_scope(constraints: constraints_hash) { instance_eval(&block) if block }
    end

    # Define defaults.
    #
    # @param defaults_hash [Hash] The default values for the scope.
    # @param block [Proc] The block for nested routes.
    # @return [Router] self.
    def defaults(defaults_hash = {}, &block)
      push_scope(defaults: defaults_hash) { instance_eval(&block) if block }
    end

    # ---- Concerns ----------------------------------------------------------

    # Define a concern.
    #
    # @param concern_name [Symbol] The concern name.
    # @param block [Proc] The block defining the concern.
    # @return [void]
    def concern(concern_name, &block)
      ensure_unfrozen!
      @concerns[concern_name] = block
    end

    # Use concerns.
    #
    # @param concern_names [Array<Symbol>] The names of the concerns to use.
    # @param block [Proc] The block for additional routes.
    # @return [void]
    def concerns(*concern_names, &block)
      concern_names.each do |name|
        concern_block = @concerns[name]
        raise "Concern '#{name}' not found" unless concern_block

        instance_eval(&concern_block)
      end
      instance_eval(&block) if block
    end

    # ---- Mounting ----------------------------------------------------------

    # Mount an app.
    #
    # @param app [Object] The app to mount.
    # @param at [String, nil] The path to mount the app at.
    # @return [void]
    def mount(app, at: nil)
      ensure_unfrozen!
      mount_path = at || "/#{app}"
      defaults = { _mounted_app: app }
      add_route(
        "#{mount_path}/*path",
        controller: 'mounted',
        action: :call,
        via: VERBS_ALL,
        defaults: defaults
      )
    end
  end
end
