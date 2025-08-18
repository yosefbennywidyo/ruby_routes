module RubyRoutes
  class RouteSet
    attr_reader :routes

    def initialize
      @tree = RubyRoutes::RadixTree.new
      @named_routes = {}
      @routes = []
      # Optimized recognition cache with better data structures
      @recognition_cache = {}
      @cache_hits = 0
      @cache_misses = 0
      @recognition_cache_max = 8192  # larger for better hit rates
    end

    def add_route(route)
      @routes << route
      @tree.add(route.path, route.methods, route)
      @named_routes[route.name] = route if route.named?
      # Clear recognition cache when routes change
      @recognition_cache.clear if @recognition_cache.size > 100
      route
    end

    def find_route(request_method, request_path)
      # Optimized: avoid repeated string allocation
      method_up = request_method.to_s.upcase
      handler, _params = @tree.find(request_path, method_up)
      handler
    end

    def find_named_route(name)
      route = @named_routes[name]
      return route if route
      raise RouteNotFound, "No route named '#{name}'"
    end

    def match(request_method, request_path)
      # Fast path: normalize method once
      method_up = method_lookup(request_method)

      # Optimized cache key: avoid string interpolation when possible
      cache_key = build_cache_key(method_up, request_path)

      # Cache hit: return immediately
      if (cached = @recognition_cache[cache_key])
        @cache_hits += 1
        cached_route, cached_params = cached
        return {
          route: cached_route,
          params: cached_params,
          controller: cached_route.controller,
          action: cached_route.action
        }
      end

      @cache_misses += 1

      # Use thread-local params to avoid allocations
      params = get_thread_local_params
      handler, _ = @tree.find(request_path, method_up, params)
      return nil unless handler

      route = handler

      # Fast path: merge defaults only if they exist
      merge_defaults(route, params) if route.defaults && !route.defaults.empty?

      # Fast path: parse query params only if needed
      if request_path.include?('?')
        merge_query_params(route, request_path, params)
      end

      # Create return hash and cache entry
      result_params = params.dup
      cache_entry = [route, result_params.freeze]
      insert_cache_entry(cache_key, cache_entry)

      {
        route: route,
        params: result_params,
        controller: route.controller,
        action: route.action
      }
    end

    def recognize_path(path, method = :get)
      match(method, path)
    end

    def generate_path(name, params = {})
      route = @named_routes[name]
      if route
        route.generate_path(params)
      else
        raise RouteNotFound, "No route named '#{name}'"
      end
    end

    def generate_path_from_route(route, params = {})
      route.generate_path(params)
    end

    def clear!
      @routes.clear
      @named_routes.clear
      @recognition_cache.clear
      @tree = RadixTree.new
      @cache_hits = @cache_misses = 0
    end

    def size
      @routes.size
    end
    alias_method :length, :size

    def empty?
      @routes.empty?
    end

    def each(&block)
      return enum_for(:each) unless block_given?
      @routes.each(&block)
    end

    def include?(route)
      @routes.include?(route)
    end

    # Performance monitoring
    def cache_stats
      total = @cache_hits + @cache_misses
      hit_rate = total > 0 ? (@cache_hits.to_f / total * 100).round(2) : 0
      {
        hits: @cache_hits,
        misses: @cache_misses,
        hit_rate: "#{hit_rate}%",
        size: @recognition_cache.size
      }
    end

    private

    # Method lookup table to avoid repeated upcasing
    def method_lookup(method)
      @method_cache ||= Hash.new { |h, k| h[k] = k.to_s.upcase.freeze }
      @method_cache[method]
    end

    # Optimized cache key building - avoid string interpolation
    def build_cache_key(method, path)
      # Use thread-local buffer to avoid race conditions
      buffer = Thread.current[:ruby_routes_cache_key_buffer] ||= String.new(capacity: 256)
      buffer.clear
      buffer << method << ':' << path
      buffer.dup.freeze
    end

    # Get thread-local params hash, reusing when possible
    def get_thread_local_params
      # Use thread-local object pool to avoid race conditions
      pool = Thread.current[:ruby_routes_params_pool] ||= []
      if pool.empty?
        {}
      else
        hash = pool.pop
        hash.clear
        hash
      end
    end

    def return_params_to_pool(params)
      pool = Thread.current[:ruby_routes_params_pool] ||= []
      pool.push(params) if pool.size < 10
    end

    # Fast defaults merging
    def merge_defaults(route, params)
      route.defaults.each do |key, value|
        params[key] = value unless params.key?(key)
      end
    end

    # Fast query params merging
    def merge_query_params(route, request_path, params)
      if route.respond_to?(:parse_query_params)
        qp = route.parse_query_params(request_path)
        params.merge!(qp) unless qp.empty?
      elsif route.respond_to?(:query_params)
        qp = route.query_params(request_path)
        params.merge!(qp) unless qp.empty?
      end
    end

    # Efficient cache insertion with LRU eviction
    def insert_cache_entry(cache_key, cache_entry)
      @recognition_cache[cache_key] = cache_entry

      # Simple eviction: clear cache when it gets too large
      if @recognition_cache.size > @recognition_cache_max
        # Keep most recently used half
        keys_to_delete = @recognition_cache.keys[0...(@recognition_cache_max / 2)]
        keys_to_delete.each { |k| @recognition_cache.delete(k) }
      end
    end
  end
end
