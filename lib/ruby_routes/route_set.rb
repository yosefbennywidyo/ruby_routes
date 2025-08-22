require_relative 'utility/key_builder_utility'

module RubyRoutes
  class RouteSet
    attr_reader :routes

    include RubyRoutes::Utility::KeyBuilderUtility

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

    FAST_METHOD_MAP = {
      get: 'GET', post: 'POST', put: 'PUT', patch: 'PATCH',
      delete: 'DELETE', head: 'HEAD', options: 'OPTIONS'
    }.freeze

    def normalize_method_input(method)
      case method
      when Symbol
        FAST_METHOD_MAP[method] || method.to_s.upcase
      when String
        # Fast path: assume already correct; fallback only for common lowercase
        return method if method.length <= 6 && method == method.upcase
        FAST_METHOD_MAP[method.downcase.to_sym] || method.upcase
      else
        s = method.to_s
        FAST_METHOD_MAP[s.downcase.to_sym] || s.upcase
      end
    end
    private :normalize_method_input

    def match(method, path)
      m = normalize_method_input(method)
      raw = path.to_s
      cache_key = cache_key_for_request(m, raw)

      # Single cache lookup with proper hit accounting
      if (hit = @recognition_cache[cache_key])
        @cache_hits += 1
        return hit
      end

      @cache_misses += 1

      path_without_query, _qs = raw.split('?', 2)

      # Use normalized method (m) for trie lookup
      route, params = @radix_tree.find(path_without_query, m)
      return nil unless route

      merge_query_params(route, raw, params)

      if route.respond_to?(:defaults) && route.defaults
        route.defaults.each { |k,v| params[k.to_s] = v unless params.key?(k.to_s) }
      end

      result = {
        route: route,
        params: params,
        controller: route.controller,
        action: route.action
      }

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
      lookups = @cache_hits + @cache_misses
      {
        hits: @cache_hits,
        misses: @cache_misses,
        hit_rate: lookups.zero? ? 0.0 : (@cache_hits.to_f / lookups * 100.0),
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

    def insert_cache_entry(key, value)
      # unchanged cache insert (key already frozen & reusable)
      if @recognition_cache.size >= @recognition_cache_max
        @recognition_cache.keys.first(@recognition_cache_max / 4).each { |k| @recognition_cache.delete(k) }
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
