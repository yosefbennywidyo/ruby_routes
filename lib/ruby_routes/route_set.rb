module RubyRoutes
  class RouteSet
    attr_reader :routes

    def initialize
      @tree = RubyRoutes::RadixTree.new
      @named_routes = {}
      @routes = []          # keep list for specs / iteration / size
      @recognition_cache = {}        # simple bounded cache: key -> [route, params]
      @recognition_cache_order = []
      @recognition_cache_max = 4096
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
      # Normalize method once and attempt recognition cache hit
      method_up = request_method.to_s.upcase
      cache_key = "#{method_up}:#{request_path}"
      if (cached = @recognition_cache[cache_key])
        # Return cached params (frozen) directly to avoid heavy dup allocations.
        cached_route, cached_params = cached
        return { route: cached_route, params: cached_params, controller: cached_route.controller, action: cached_route.action }
      end

      # Use a thread-local hash as output for RadixTree to avoid allocating a params Hash
      tmp = Thread.current[:ruby_routes_params] ||= {}
      handler, _ = @tree.find(request_path, method_up, tmp)
      return nil unless handler
      route = handler

      # tmp now contains path params (filled by RadixTree). Merge defaults and query params in-place.
      # defaults first (only set missing keys)
      if route.defaults
        route.defaults.each { |k, v| tmp[k] = v unless tmp.key?(k) }
      end
      if request_path.include?('?')
        qp = route.parse_query_params(request_path)
        qp.each { |k, v| tmp[k] = v } unless qp.empty?
      end

      params = tmp.dup

      # insert into bounded recognition cache (store frozen params to reduce accidental mutation)
      @recognition_cache[cache_key] = [route, params.freeze]
      @recognition_cache_order << cache_key
      if @recognition_cache_order.size > @recognition_cache_max
        oldest = @recognition_cache_order.shift
        @recognition_cache.delete(oldest)
      end

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
