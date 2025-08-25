require_relative 'utility/route_utility'
require_relative 'utility/inflector_utility'

module RubyRoutes
  # Router
  #
  # Public DSL entrypoint for defining application routes.
  #
  # Responsibilities:
  # - Provides Rails‑inspired methods (get/post/put/patch/delete/match).
  # - Resourceful routing helpers (#resources / #resource).
  # - Scoping helpers: #namespace, #scope, #constraints, #defaults.
  # - Reusable block groups via #concern / #concerns.
  # - Mounting external Rack apps (#mount).
  # - Builds and delegates to an underlying RouteSet.
  #
  # Scoping Stack:
  # - Each scope pushes a hash (path/module/constraints/defaults).
  # - New routes inherit merged values when defined.
  #
  # Thread safety: Define routes at boot (not thread‑safe for runtime mutation).
  #
  # @api public
  class Router
    # @return [RouteSet] container of all compiled routes
    attr_reader :route_set

    # Create a new Router and evaluate an optional DSL block.
    #
    # @yield (optional) route definition block
    def initialize(&block)
      @route_set   = RouteSet.new
      @route_utils = RubyRoutes::Utility::RouteUtility.new(@route_set)
      @scope_stack = []
      @concerns    = {}
      instance_eval(&block) if block_given?
    end

    # ------------------------------------------------------------------
    # HTTP Verb Helpers
    # ------------------------------------------------------------------

    # Define a GET route.
    def get(path, options = {})      ; add_route(path, options.merge(via: :get))    ; end
    # Define a POST route.
    def post(path, options = {})     ; add_route(path, options.merge(via: :post))   ; end
    # Define a PUT route.
    def put(path, options = {})      ; add_route(path, options.merge(via: :put))    ; end
    # Define a PATCH route.
    def patch(path, options = {})    ; add_route(path, options.merge(via: :patch))  ; end
    # Define a DELETE route.
    def delete(path, options = {})   ; add_route(path, options.merge(via: :delete)) ; end

    # Define a route accepting explicit :via or multiple verbs.
    #
    # @param path [String]
    # @param options [Hash] must include :via or defaults handled by Route
    def match(path, options = {})
      add_route(path, options)
    end

    # ------------------------------------------------------------------
    # Resourceful Routing
    # ------------------------------------------------------------------

    # Define plural resource routes (index, new, create, show, edit, update, destroy).
    #
    # Supports nested resources via :nested option and nested block DSL.
    #
    # @param name [Symbol,String]
    # @param options [Hash] :path, :controller, :nested
    # @yield optional nested block
    def resources(name, options = {}, &block)
      base_name   = name.to_s
      plural_path  = RubyRoutes::Utility::InflectorUtility.pluralize(options[:path] || base_name)
      singular     = RubyRoutes::Utility::InflectorUtility.singularize(base_name)
      plural      = (options[:path] || name.to_s.pluralize)
      controller  = options[:controller] || plural

      # Collection
      get   "/#{plural}",             options.merge(to: "#{controller}#index")
      get   "/#{plural}/new",         options.merge(to: "#{controller}#new")
      post  "/#{plural}",             options.merge(to: "#{controller}#create")

      # Member
      get   "/#{plural}/:id",         options.merge(to: "#{controller}#show")
      get   "/#{plural}/:id/edit",    options.merge(to: "#{controller}#edit")
      put   "/#{plural}/:id",         options.merge(to: "#{controller}#update")
      patch "/#{plural}/:id",         options.merge(to: "#{controller}#update")
      delete "/#{plural}/:id",        options.merge(to: "#{controller}#destroy")

      # Simple nested resource support
      if options[:nested]
        nested_name     = options[:nested]
        nested_plural   = nested_name.to_s.pluralize

        get   "/#{plural}/:id/#{nested_plural}",                      options.merge(to: "#{nested_plural}#index")
        get   "/#{plural}/:id/#{nested_plural}/new",                  options.merge(to: "#{nested_plural}#new")
        post  "/#{plural}/:id/#{nested_plural}",                      options.merge(to: "#{nested_plural}#create")
        get   "/#{plural}/:id/#{nested_plural}/:nested_id",           options.merge(to: "#{nested_plural}#show")
        get   "/#{plural}/:id/#{nested_plural}/:nested_id/edit",      options.merge(to: "#{nested_plural}#edit")
        put   "/#{plural}/:id/#{nested_plural}/:nested_id",           options.merge(to: "#{nested_plural}#update")
        patch "/#{plural}/:id/#{nested_plural}/:nested_id",           options.merge(to: "#{nested_plural}#update")
        delete "/#{plural}/:id/#{nested_plural}/:nested_id",          options.merge(to: "#{nested_plural}#destroy")
      end

      if block_given?
        @scope_stack.push({ path: "/#{plural}/:id" })
        begin
          instance_eval(&block)
        ensure
          @scope_stack.pop
        end
      end
    end

    # Define singular resource routes (show, new, create, edit, update, destroy).
    #
    # @param name [Symbol,String]
    # @param options [Hash]
    def resource(name, options = {})
      singular    = RubyRoutes::Utility::InflectorUtility.singularize(name.to_s)
      controller  = options[:controller] || singular
      get    "/#{singular}",       options.merge(to: "#{singular}#show")
      get    "/#{singular}/new",   options.merge(to: "#{singular}#new")
      post   "/#{singular}",       options.merge(to: "#{singular}#create")
      get    "/#{singular}/edit",  options.merge(to: "#{singular}#edit")
      put    "/#{singular}",       options.merge(to: "#{singular}#update")
      patch  "/#{singular}",       options.merge(to: "#{singular}#update")
      delete "/#{singular}",       options.merge(to: "#{singular}#destroy")
    end

    # ------------------------------------------------------------------
    # Scoping
    # ------------------------------------------------------------------

    # Namespace routes (adds path + module prefix).
    #
    # @param name [String,Symbol]
    def namespace(name, options = {}, &block)
      @scope_stack.push({ path: "/#{name}", module: name })
      instance_eval(&block) if block_given?
      @scope_stack.pop
    end

    # Generic scope for path/module/constraints/defaults.
    #
    # @param options_or_path [Hash,String]
    def scope(options_or_path = {}, &block)
      options = options_or_path.is_a?(String) ? { path: options_or_path } : options_or_path
      @scope_stack.push(options)
      instance_eval(&block) if block_given?
      @scope_stack.pop
    end

    # Define root ("/") route (GET).
    def root(options = {})
      add_route("/", options.merge(via: :get))
    end

    # Register reusable concern blocks by name.
    #
    # @param name [Symbol]
    def concern(name, &block)
      @concerns[name] = block
    end

    # Include previously defined concerns and optionally a block.
    #
    # @param names [Array<Symbol>]
    def concerns(*names, &block)
      names.each do |name|
        concern = @concerns[name]
        raise "Concern '#{name}' not found" unless concern
        instance_eval(&concern)
      end
      instance_eval(&block) if block_given?
    end

    # Apply constraints (merged into scope).
    #
    # @param constraints [Hash]
    def constraints(constraints = {}, &block)
      @scope_stack.push({ constraints: constraints })
      instance_eval(&block) if block_given?
      @scope_stack.pop
    end

    # Apply default params (merged into scope).
    #
    # @param defaults [Hash]
    def defaults(defaults = {}, &block)
      @scope_stack.push({ defaults: defaults })
      instance_eval(&block) if block_given?
      @scope_stack.pop
    end

    # Mount an external Rack (or Rack‑compatible) app at a path.
    #
    # Usage:
    #   mount MyRackApp, at: "/app"
    #   mount ->(env) { [200, {'Content-Type'=>'text/plain'}, ['OK']] }, at: "/lambda"
    #
    # Implementation detail:
    # - Route currently requires controller/action; we map to a synthetic
    #   controller + :call action so validation passes.
    # - The actual rack app object is stored in defaults under :_mounted_app
    #   so downstream dispatcher can fetch and invoke it.
    #
    # If you later relax Route validation to allow direct callables,
    # you can switch to: add_route("#{path}/*path", to: app, via: VERBS_ALL)
    VERBS_ALL = [:get, :post, :put, :patch, :delete, :head, :options].freeze

    def mount(app, at: nil)
      mount_path = at || "/#{app}"
      # Synthetic controller/action identifiers
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

    # Internal route add after applying scope stack.
    def add_route(path, options = {})
      scoped = apply_scope(path, options)
      @route_utils.define(scoped[:path], scoped)
    end

    # Merge scopes into final path/options.
    #
    # Precedence: innermost (last pushed) overrides outer keys when merging.
    def apply_scope(path, options)
      scoped_options = options.dup
      scoped_path    = path

      @scope_stack.reverse_each do |scope|
        scoped_path = "#{scope[:path]}#{scoped_path}" if scope[:path]

        if scope[:module] && scoped_options[:to]
          controller = scoped_options[:to].to_s.split('#').first
          action     = scoped_options[:to].to_s.split('#').last
          scoped_options[:to] = "#{scope[:module]}/#{controller}##{action}"
        end

        if scope[:constraints]
          scoped_options[:constraints] = (scoped_options[:constraints] || {}).merge(scope[:constraints])
        end

        if scope[:defaults]
          scoped_options[:defaults] = (scoped_options[:defaults] || {}).merge(scope[:defaults])
        end
      end

      scoped_options[:path] = scoped_path
      scoped_options
    end
  end
end
