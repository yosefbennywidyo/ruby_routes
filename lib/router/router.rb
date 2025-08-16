module Router
  class RouterClass
    attr_reader :route_set

    def initialize(&block)
      @route_set = RouteSet.new
      @scope_stack = []
      instance_eval(&block) if block_given?
    end

    # Basic route definition
    def get(path, options = {})
      add_route(path, options.merge(via: :get))
    end

    def post(path, options = {})
      add_route(path, options.merge(via: :post))
    end

    def put(path, options = {})
      add_route(path, options.merge(via: :put))
    end

    def patch(path, options = {})
      add_route(path, options.merge(via: :patch))
    end

    def delete(path, options = {})
      add_route(path, options.merge(via: :delete))
    end

    def match(path, options = {})
      add_route(path, options)
    end

    # Resources routing (Rails-like)
    def resources(name, options = {}, &block)
      singular = name.to_s.singularize
      plural = name.to_s.pluralize
      
      # Collection routes
      get "/#{plural}", options.merge(to: "#{plural}#index")
      get "/#{plural}/new", options.merge(to: "#{plural}#new")
      post "/#{plural}", options.merge(to: "#{plural}#create")
      
      # Member routes
      get "/#{plural}/:id", options.merge(to: "#{plural}#show")
      get "/#{plural}/:id/edit", options.merge(to: "#{plural}#edit")
      put "/#{plural}/:id", options.merge(to: "#{plural}#update")
      patch "/#{plural}/:id", options.merge(to: "#{plural}#update")
      delete "/#{plural}/:id", options.merge(to: "#{plural}#destroy")
      
      # Nested resources if specified
      if options[:nested]
        nested_name = options[:nested]
        nested_singular = nested_name.to_s.singularize
        nested_plural = nested_name.to_s.pluralize
        
        get "/#{plural}/:id/#{nested_plural}", options.merge(to: "#{nested_plural}#index")
        get "/#{plural}/:id/#{nested_plural}/new", options.merge(to: "#{nested_plural}#new")
        post "/#{plural}/:id/#{nested_plural}", options.merge(to: "#{nested_plural}#create")
        get "/#{plural}/:id/#{nested_plural}/:nested_id", options.merge(to: "#{nested_plural}#show")
        get "/#{plural}/:id/#{nested_plural}/:nested_id/edit", options.merge(to: "#{nested_plural}#edit")
        put "/#{plural}/:id/#{nested_plural}/:nested_id", options.merge(to: "#{nested_plural}#update")
        patch "/#{plural}/:id/#{nested_plural}/:nested_id", options.merge(to: "#{nested_plural}#update")
        delete "/#{plural}/:id/#{nested_plural}/:nested_id", options.merge(to: "#{nested_plural}#update")
        delete "/#{plural}/:id/#{nested_plural}/:nested_id", options.merge(to: "#{nested_plural}#destroy")
      end
      
      # Handle concerns if block is given
      if block_given?
        # Push a scope for nested resources
        @scope_stack.push({ path: "/#{plural}/:id" })
        # Execute the block in the context of this router instance
        instance_eval(&block)
        @scope_stack.pop
      end
    end

    def resource(name, options = {})
      singular = name.to_s.singularize
      
      get "/#{singular}", options.merge(to: "#{singular}#show")
      get "/#{singular}/new", options.merge(to: "#{singular}#new")
      post "/#{singular}", options.merge(to: "#{singular}#create")
      get "/#{singular}/edit", options.merge(to: "#{singular}#edit")
      put "/#{singular}", options.merge(to: "#{singular}#update")
      patch "/#{singular}", options.merge(to: "#{singular}#update")
      delete "/#{singular}", options.merge(to: "#{singular}#destroy")
    end

    # Namespace support
    def namespace(name, options = {}, &block)
      @scope_stack.push({ path: "/#{name}", module: name })
      
      if block_given?
        instance_eval(&block)
      end
      
      @scope_stack.pop
    end

    # Scope support
    def scope(options = {}, &block)
      @scope_stack.push(options)
      
      if block_given?
        instance_eval(&block)
      end
      
      @scope_stack.pop
    end

    # Root route
    def root(options = {})
      add_route("/", options.merge(via: :get))
    end

    # Concerns (reusable route groups)
    def concerns(*names, &block)
      names.each do |name|
        concern = @concerns[name]
        raise "Concern '#{name}' not found" unless concern
        
        instance_eval(&concern)
      end
      
      if block_given?
        instance_eval(&block)
      end
    end

    def concern(name, &block)
      @concerns ||= {}
      @concerns[name] = block
    end

    # Route constraints
    def constraints(constraints = {}, &block)
      @scope_stack.push({ constraints: constraints })
      
      if block_given?
        instance_eval(&block)
      end
      
      @scope_stack.pop
    end

    # Defaults
    def defaults(defaults = {}, &block)
      @scope_stack.push({ defaults: defaults })
      
      if block_given?
        instance_eval(&block)
      end
      
      @scope_stack.pop
    end

    # Mount other applications
    def mount(app, at: nil)
      path = at || "/#{app}"
      add_route("#{path}/*path", to: app, via: :all)
    end

    private

    def add_route(path, options = {})
      # Apply current scope
      scoped_options = apply_scope(path, options)
      
      # Create and add the route
      route = Route.new(scoped_options[:path], scoped_options)
      @route_set.add_route(route)
      route
    end

    def apply_scope(path, options)
      scoped_options = options.dup
      scoped_path = path
      
      @scope_stack.reverse_each do |scope|
        if scope[:path]
          scoped_path = "#{scope[:path]}#{scoped_path}"
        end
        
        if scope[:module] && scoped_options[:to]
          controller = scoped_options[:to].to_s.split('#').first
          scoped_options[:to] = "#{scope[:module]}/#{controller}##{scoped_options[:to].to_s.split('#').last}"
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
