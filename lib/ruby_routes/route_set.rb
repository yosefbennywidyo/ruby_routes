module RubyRoutes
  class RouteSet
    attr_reader :routes

    def initialize
      @tree = RubyRoutes::RadixTree.new
      @named_routes = {}
      @routes = []          # keep list for specs / iteration / size
    end

    def add_route(route)
      @routes << route
      @tree.add(route.path, route.methods, route)
      @named_routes[route.name] = route if route.named?
      route
    end

    def find_route(request_method, request_path)
      # Return the Route object (or nil) to match spec expectations.
      handler, _params = @tree.find(request_path, request_method.to_s.upcase)
      handler
    end

    def find_named_route(name)
      @named_routes[name] or raise RouteNotFound, "No route named '#{name}'"
    end

    def match(request_method, request_path)
      # Use the radix tree directly so we can access the params returned by the tree.
      handler, params = @tree.find(request_path, request_method.to_s.upcase)
      return nil unless handler

      route = handler

      {
        route: route,
        params: route.extract_params(request_path),
        controller: route.controller,
        action: route.action
      }
    end

    def recognize_path(path, method = :get)
      match(method, path)
    end

    def generate_path(name, params = {})
      route = find_named_route(name)
      generate_path_from_route(route, params)
    end

    def generate_path_from_route(route, params = {})
      path = route.path.dup

      params.each do |key, value|
        path.gsub!(":#{key}", value.to_s)
      end

      # Remove any remaining :param placeholders
      path.gsub!(/\/:[^\/]+/, '')
      path.gsub!(/\/$/, '') if path != '/'

      path
    end

    def clear!
      @routes.clear
      @named_routes.clear
      @tree = RubyRoutes::RadixTree.new
    end

    def size
      @routes.size
    end

    def empty?
      @routes.empty?
    end

    def each(&block)
      @routes.each(&block)
    end

    def include?(route)
      @routes.include?(route)
    end
  end
end
