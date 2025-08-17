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
      # Use RadixTree lookup and the path params it returns (avoid reparsing the path)
      handler, path_params = @tree.find(request_path, request_method.to_s.upcase)
      return nil unless handler

      route = handler

      # Reuse a thread-local hash to reduce temporary allocations when building params.
      tmp = Thread.current[:ruby_routes_params] ||= {}
      tmp.clear
      if route.defaults
        route.defaults.each { |k, v| tmp[k] = v }
      end
      if path_params
        path_params.each { |k, v| tmp[k] = v }
      end
      qp = route.parse_query_params(request_path)
      qp.each { |k, v| tmp[k] = v } unless qp.empty?

      # Return a fresh hash to callers (don't expose the thread-local directly)
      params = tmp.dup

      # Note: lightweight constraint checks are performed during RadixTree#find.
      # Skip full constraint re-validation here to avoid double work.

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
      # Delegate to Route#generate_path which uses precompiled segments + cache
      route.generate_path(params)
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
