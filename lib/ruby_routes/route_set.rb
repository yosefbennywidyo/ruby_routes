module RubyRoutes
  class RouteSet
    attr_reader :routes

    def initialize
      @routes = []
      @named_routes = {}
      @recognition_cache = {}
      @recognition_cache_max = 2048
      @cache_hits = 0
      @cache_misses = 0
      @radix_tree = RadixTree.new
    end

    def add_to_collection(route)
      @routes << route
      @radix_tree.add(route.path, route.methods, route)
      @named_routes[route.name] = route if route.named?
    end

    alias_method :add_route, :add_to_collection

    def find_route(method, path)
      route, _ = @radix_tree.find(path, method)
      route
    end

    def find_named_route(name)
      route = @named_routes[name]
      raise RouteNotFound.new("No route named '#{name}'") unless route
      route
    end

    def match(method, path)
      cache_key = build_cache_key(method, path)

      # Check cache first
      if @recognition_cache.key?(cache_key)
        @cache_hits += 1
        return @recognition_cache[cache_key]
      end

      @cache_misses += 1

      # Extract path without query string for lookup
      path_without_query, query_string = path.to_s.split('?', 2)

      # Find the route
      route, params = @radix_tree.find(path_without_query, method)
      return nil unless route

      # Extract and merge query parameters
      merge_query_params(route, path, params)

      # Apply defaults from route
      if route.respond_to?(:defaults) && route.defaults
        route.defaults.each do |key, value|
          params[key.to_s] = value unless params.key?(key.to_s)
        end
      end

      # Build the result hash
      result = {
        route: route,
        params: params,
        controller: route.controller,
        action: route.action
      }

      # Cache the result
      insert_cache_entry(cache_key, result)

      result
    end

    def recognize_path(path, method = 'GET')
      match(method, path)
    end

    def generate_path(name, params = {})
      route = find_named_route(name)
      route.generate_path(params)
    end

    def generate_path_from_route(route, params = {})
      route.generate_path(params)
    end

    def clear!
      @routes.clear
      @named_routes.clear
      @recognition_cache.clear
      @cache_hits = 0
      @cache_misses = 0
      # Create a new radix tree since we can't clear it
      @radix_tree = RadixTree.new
    end

    def size
      @routes.size
    end

    def empty?
      @routes.empty?
    end

    def cache_stats
      {
        hits: @cache_hits,
        misses: @cache_misses,
        hit_rate: size > 0 ? (@cache_hits.to_f / (@cache_hits + @cache_misses) * 100.0) : 0.0,
        size: @recognition_cache.size
      }
    end

    def each(&block)
      @routes.each(&block)
    end

    def include?(route)
      @routes.include?(route)
    end

    private

    def build_cache_key(method, path)
      "#{method}:#{path}"
    end

    def insert_cache_entry(key, value)
      # Implement LRU-like behavior by evicting oldest entries when too many
      if @recognition_cache.size >= @recognition_cache_max
        # Remove a significant batch of oldest entries - 25% of max size
        keys_to_remove = @recognition_cache.keys.first(@recognition_cache_max / 4)
        keys_to_remove.each do |old_key|
          @recognition_cache.delete(old_key)
        end
      end

      @recognition_cache[key] = value
    end

    # Add the missing method for merging query params
    def merge_query_params(route, path, params)
      # Check for query string
      if path.to_s.include?('?')
        if route.respond_to?(:parse_query_params)
          query_params = route.parse_query_params(path)
          params.merge!(query_params) if query_params
        elsif route.respond_to?(:query_params)
          query_params = route.query_params(path)
          params.merge!(query_params) if query_params
        end
      end
    end

    # Add thread-local params pool methods
    def get_thread_local_params
      thread_params = Thread.current[:ruby_routes_params_pool] ||= []
      if thread_params.empty?
        {}
      else
        thread_params.pop.clear
      end
    end

    def return_params_to_pool(params)
      params.clear
      thread_pool = Thread.current[:ruby_routes_params_pool] ||= []
      thread_pool << params if thread_pool.size < 10 # Limit pool size
    end
  end
end
