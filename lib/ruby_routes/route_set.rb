module RubyRoutes
  class RouteSet
    attr_reader :routes

    def initialize
      @routes = []
      @named_routes = {}
      @radix_tree = RubyRoutes::RadixTree.new
    end

    def add_route(route)
      @routes << route
      @named_routes[route.name] = route if route.named?
      # Add to radix tree for fast lookup
      route.methods.each do |method|
        @radix_tree.add_route(route.path, method, route, constraints: route.constraints)
      end
      route
    end

    def find_route(request_method, request_path)
      handler_info, params = @radix_tree.find_route(request_path, request_method.to_s.upcase)
      handler_info ? handler_info[:handler] : nil
    end

    def find_named_route(name)
      @named_routes[name] or raise RouteNotFound, "No route named '#{name}'"
    end

    def match(request_method, request_path)
      route = find_route(request_method, request_path)
      return nil unless route

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
