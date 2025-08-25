# frozen_string_literal: true
# Public DSL entrypoint for defining application routes.
#
# Typical usage:
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
#   - Provide Rails‑inspired DSL (get/post/put/patch/delete/match/root).
#   - Define RESTful collections via #resources and singular via #resource.
#   - Support scoping (namespace / scope / constraints / defaults).
#   - Allow reusable blocks via concerns (#concern / #concerns).
#   - Mount external Rack apps (#mount).
#   - Delegate route object creation & storage to RouteSet / RouteUtility.
#
# Design Notes:
#   - Scope stack is an array of shallow hashes (path/module/constraints/defaults).
#   - Scopes are merged from outer → inner (reverse_each) when materializing a route.
#   - Options hashes passed by user are duplicated only when necessary
#     (see build_route_options) to reduce allocation churn.
#
# Public API Surface (Stable):
#   - #initialize (block form)
#   - HTTP verb helpers (get/post/put/patch/delete/match)
#   - #root
#   - #resources / #resource
#   - #namespace / #scope / #constraints / #defaults
#   - #concern / #concerns
#   - #mount
#
# Internal / Subject to Change:
#   - #add_route
#   - #apply_scope
#   - #build_route_options
#   - #push_scope
#
module RubyRoutes
  class Router
    # All HTTP verbs supported by #mount helper.
    VERBS_ALL = [:get, :post, :put, :patch, :delete, :head, :options].freeze

    # @return [RouteSet] container of compiled Route objects.
    attr_reader :route_set

    # Create a new Router with optional DSL block.
    #
    # @yield [self] optional route definition block
    def initialize(&block)
      @route_set   = RouteSet.new
      @route_utils = RubyRoutes::Utility::RouteUtility.new(@route_set)
      @scope_stack = []
      @concerns    = {}
      instance_eval(&block) if block_given?
    end

    # ---- HTTP Verb Helpers -------------------------------------------------

    # Define a GET route.
    # @param path [String]
    # @param options [Hash] :to, :controller/:action, :constraints, :defaults, :via (ignored if provided)
    def get(path, options = {})      ; add_route(path, build_route_options(options, :get))    ; end
    # Define a POST route.
    def post(path, options = {})     ; add_route(path, build_route_options(options, :post))   ; end
    # Define a PUT route.
    def put(path, options = {})      ; add_route(path, build_route_options(options, :put))    ; end
    # Define a PATCH route.
    def patch(path, options = {})    ; add_route(path, build_route_options(options, :patch))  ; end
    # Define a DELETE route.
    def delete(path, options = {})   ; add_route(path, build_route_options(options, :delete)) ; end

    # Generic multi‑verb matcher.
    # Caller must supply :via => symbol or array of symbols.
    # @param path [String]
    # @param options [Hash] must include :via
    def match(path, options = {})
      add_route(path, options)
    end

    # Define root ("/") route (GET).
    # @param options [Hash]
    def root(options = {})
      add_route("/", options.merge(via: :get))
    end

    # ---- RESTful Resources -------------------------------------------------

    # Plural resource routes.
    #
    # Generated collection routes:
    #   GET    /<resource>          -> controller#index
    #   GET    /<resource>/new      -> controller#new
    #   POST   /<resource>          -> controller#create
    #
    # Generated member routes:
    #   GET    /<resource>/:id          -> controller#show
    #   GET    /<resource>/:id/edit     -> controller#edit
    #   PUT    /<resource>/:id          -> controller#update
    #   PATCH  /<resource>/:id          -> controller#update
    #   DELETE /<resource>/:id          -> controller#destroy
    #
    # Options:
    #   :path        - override URL segment (e.g. path: 'acct')
    #   :controller  - override controller segment
    #   :nested      - (legacy) single nested resource name
    #
    # Block:
    #   Yields nested DSL within /<resource>/:id scope.
    #
    # @param name [Symbol,String]
    # @param options [Hash]
    def resources(name, options = {}, &block)
      base_name     = name.to_s
      resource_path = options[:path] ? options[:path].to_s : RubyRoutes::Utility::InflectorUtility.pluralize(base_name)
      controller    = options[:controller] || resource_path

      # Precompute "controller#action" strings once
      to_index   = "#{controller}#index"
      to_new     = "#{controller}#new"
      to_create  = "#{controller}#create"
      to_show    = "#{controller}#show"
      to_edit    = "#{controller}#edit"
      to_update  = "#{controller}#update"
      to_destroy = "#{controller}#destroy"

      push_scope(path: "/#{resource_path}") do
        # Collection
        add_route('',      build_route_options(options, :get,  to_index))
        add_route('/new',  build_route_options(options, :get,  to_new))
        add_route('',      build_route_options(options, :post, to_create))

        # Member
        add_route('/:id',      build_route_options(options, :get,    to_show))
        add_route('/:id/edit', build_route_options(options, :get,    to_edit))
        add_route('/:id',      build_route_options(options, :put,    to_update))
        add_route('/:id',      build_route_options(options, :patch,  to_update))
        add_route('/:id',      build_route_options(options, :delete, to_destroy))

        if options[:nested]
          nested_name   = options[:nested].to_s
          nested_plur   = RubyRoutes::Utility::InflectorUtility.pluralize(nested_name)
          nested_ctrl   = nested_plur
          n_index   = "#{nested_ctrl}#index"
            n_new     = "#{nested_ctrl}#new"
          n_create  = "#{nested_ctrl}#create"
          n_show    = "#{nested_ctrl}#show"
          n_edit    = "#{nested_ctrl}#edit"
          n_update  = "#{nested_ctrl}#update"
          n_destroy = "#{nested_ctrl}#destroy"

          push_scope(path: '/:id') do
            push_scope(path: "/#{nested_plur}") do
              add_route('',                build_route_options(options, :get,    n_index))
              add_route('/new',            build_route_options(options, :get,    n_new))
              add_route('',                build_route_options(options, :post,   n_create))
              add_route('/:nested_id',     build_route_options(options, :get,    n_show))
              add_route('/:nested_id/edit', build_route_options(options, :get,   n_edit))
              add_route('/:nested_id',     build_route_options(options, :put,    n_update))
              add_route('/:nested_id',     build_route_options(options, :patch,  n_update))
              add_route('/:nested_id',     build_route_options(options, :delete, n_destroy))
            end
          end
        end

        push_scope(path: '/:id') { instance_eval(&block) } if block
      end
    end

    # Singular resource routes (no collection index).
    #
    # Generated routes:
    #   GET    /<name>        -> controller#show
    #   GET    /<name>/new    -> controller#new
    #   POST   /<name>        -> controller#create
    #   GET    /<name>/edit   -> controller#edit
    #   PUT    /<name>        -> controller#update
    #   PATCH  /<name>        -> controller#update
    #   DELETE /<name>        -> controller#destroy
    #
    # @param name [Symbol,String]
    # @param options [Hash]
    def resource(name, options = {})
      singular    = RubyRoutes::Utility::InflectorUtility.singularize(name.to_s)
      controller  = options[:controller] || singular
      get    "/#{singular}",       options.merge(to: "#{controller}#show")
      get    "/#{singular}/new",   options.merge(to: "#{controller}#new")
      post   "/#{singular}",       options.merge(to: "#{controller}#create")
      get    "/#{singular}/edit",  options.merge(to: "#{controller}#edit")
      put    "/#{singular}",       options.merge(to: "#{controller}#update")
      patch  "/#{singular}",       options.merge(to: "#{controller}#update")
      delete "/#{singular}",       options.merge(to: "#{controller}#destroy")
    end

    # ---- Scoping & Namespaces ----------------------------------------------

    # Namespace routes under a path & controller module prefix.
    #
    # @param name [String,Symbol]
    # @param options [Hash] additional scope keys (constraints/defaults)
    def namespace(name, options = {}, &block)
      push_scope({ path: "/#{name}", module: name }.merge(options)) { instance_eval(&block) if block }
    end

    # Arbitrary scope wrapper for path/module/constraints/defaults.
    #
    # @param options_or_path [Hash,String]
    def scope(options_or_path = {}, &block)
      entry = options_or_path.is_a?(String) ? { path: options_or_path } : options_or_path
      push_scope(entry) { instance_eval(&block) if block }
    end

    # Apply constraints to nested routes.
    # @param constraints [Hash]
    def constraints(constraints = {}, &block)
      push_scope(constraints: constraints) { instance_eval(&block) if block }
    end

    # Apply default parameter values to nested routes.
    # @param defaults [Hash]
    def defaults(defaults = {}, &block)
      push_scope(defaults: defaults) { instance_eval(&block) if block }
    end

    # ---- Concerns ----------------------------------------------------------

    # Register a reusable DSL block.
    # @param name [Symbol]
    def concern(name, &block)
      @concerns[name] = block
    end

    # Include one or more registered concerns (and optional extra block).
    # @param names [Array<Symbol>]
    def concerns(*names, &block)
      names.each do |nm|
        c = @concerns[nm]
        raise "Concern '#{nm}' not found" unless c
        instance_eval(&c)
      end
      instance_eval(&block) if block
    end

    # ---- Mounting ----------------------------------------------------------

    # Mount a Rack app at a given path (captures remainder as *path).
    #
    # @param app [#call]
    # @param at [String] mount path (defaults to "/#{app}")
    def mount(app, at: nil)
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

    private

    # Push a scope entry with ensure-pop semantics.
    # @api private
    def push_scope(entry)
      @scope_stack.push(entry)
      return unless block_given?
      begin
        yield
      ensure
        @scope_stack.pop
      end
    end

    # Materialize route options with scope stack.
    # @api private
    def add_route(path, options = {})
      scoped = apply_scope(path, options)
      @route_utils.define(scoped[:path], scoped)
    end

    # Apply scope stack to (path, options).
    # @api private
    def apply_scope(path, options)
      scoped_options = options.dup
      scoped_path    = path

      @scope_stack.reverse_each do |scope|
        scoped_path = "#{scope[:path]}#{scoped_path}" if scope[:path]

        if scope[:module] && scoped_options[:to]
          controller, action = scoped_options[:to].to_s.split('#', 2)
          scoped_options[:to] = "#{scope[:module]}/#{controller}##{action}"
        end

        if (c = scope[:constraints])
          scoped_options[:constraints] = (scoped_options[:constraints] || {}).merge(c)
        end

        if (d = scope[:defaults])
          scoped_options[:defaults] = (scoped_options[:defaults] || {}).merge(d)
        end
      end

      scoped_options[:path] = scoped_path
      scoped_options
    end

    # Build options for route definition with minimal allocation.
    # @api private
    def build_route_options(base_opts, via_sym = nil, to_string = nil)
      needs_via = via_sym && !base_opts.key?(:via)
      needs_to  = to_string && !base_opts.key?(:to)
      return base_opts unless needs_via || needs_to
      dup = base_opts.dup
      dup[:via] = via_sym if needs_via
      dup[:to]  = to_string if needs_to
      dup
    end
  end
end
