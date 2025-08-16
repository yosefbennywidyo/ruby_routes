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
      # Use the radix tree result (params already parsed) to avoid reparsing the path.
      handler, path_params = @tree.find(request_path, request_method.to_s.upcase)
      return nil unless handler

      route = handler

      # path_params have string keys after the radix_tree change
      params = (path_params || {}).transform_keys(&:to_s)
      # merge defaults and query params (query parsing is private on Route)
      params = route.defaults.transform_keys(&:to_s).merge(params)
      params.merge!(route.send(:query_params, request_path))
      # validate constraints (private)
      route.send(:validate_constraints!, params)

      {
        route: route,
        params: params,
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
      @tree = RadixTree.new
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
