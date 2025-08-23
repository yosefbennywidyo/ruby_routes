require_relative 'utility/key_builder_utility'
require_relative 'utility/method_utility'

module RubyRoutes
  # RouteSet
  #
  # Collection + lookup facade for Route instances.
  #
  # Responsibilities:
  # - Hold all defined routes (ordered).
  # - Index named routes.
  # - Provide fast recognition (method + path → route, params) with
  #   a small in‑memory recognition cache.
  # - Delegate structural path matching to an internal RadixTree.
  #
  # Thread safety: not thread‑safe; build during boot, read per request.
  #
  # @api public (primary integration surface)
  class RouteSet
    attr_reader :routes

    include RubyRoutes::Utility::KeyBuilderUtility
    include RubyRoutes::Utility::MethodUtility

    # Initialize empty collection and caches.
    def initialize
      @routes               = []
      @named_routes         = {}
      @recognition_cache    = {}
      @recognition_cache_max = 2048
      @cache_hits           = 0
      @cache_misses         = 0
      @radix_tree           = RadixTree.new
    end

    # Add a route object to internal structures.
    #
    # @param route_obj [Route]
    # @return [Route]
    def add_to_collection(route_obj)
      @routes << route_obj
      @radix_tree.add(route_obj.path, route_obj.methods, route_obj)
      @named_routes[route_obj.name] = route_obj if route_obj.named?
      route_obj
    end
    alias_method :add_route, :add_to_collection

    # Find any route (no params) for a method/path.
    #
    # @param http_method [String, Symbol]
    # @param path [String]
    # @return [Route, nil]
    def find_route(http_method, path)
      found_route, _unused_params = @radix_tree.find(path, http_method)
      found_route
    end

    # Retrieve a named route.
    #
    # @param name [Symbol, String]
    # @return [Route]
    # @raise [RouteNotFound]
    def find_named_route(name)
      route = @named_routes[name]
      raise RouteNotFound.new("No route named '#{name}'") unless route
      route
    end

    # Recognize a request (method + path) returning route + params.
    #
    # @param http_method [String, Symbol]
    # @param path [String]
    # @return [Hash, nil] { route:, params:, controller:, action: }
    def match(http_method, path)
      normalized_method = (
        http_method.is_a?(String) && normalize_http_method(http_method).equal?(http_method)
      ) ? http_method : normalize_http_method(http_method)

      raw_path   = path.to_s
      lookup_key = cache_key_for_request(normalized_method, raw_path)

      if (cached_entry = @recognition_cache[lookup_key])
        @cache_hits += 1
        return cached_entry
      end
      @cache_misses += 1

      path_without_query, _query = raw_path.split('?', 2)

      matched_route, extracted_params = @radix_tree.find(path_without_query, normalized_method)
      return nil unless matched_route

      merge_query_params(matched_route, raw_path, extracted_params)

      if matched_route.respond_to?(:defaults) && matched_route.defaults
        matched_route.defaults.each { |key, value| extracted_params[key] = value unless extracted_params.key?(key) }
      end

      result = {
        route: matched_route,
        params: extracted_params,
        controller: matched_route.controller,
        action: matched_route.action
      }

      insert_cache_entry(lookup_key, result)
      result
    end

    # Convenience alias for Rack‑style recognizer.
    #
    # @param path [String]
    # @param method [String, Symbol]
    # @return [Hash, nil]
    def recognize_path(path, method = 'GET')
      match(method, path)
    end

    # Generate path via named route.
    #
    # @param name [Symbol, String]
    # @param params [Hash]
    # @return [String]
    def generate_path(name, params = {})
      route = find_named_route(name)
      route.generate_path(params)
    end

    # Generate path from a direct route reference.
    #
    # @param route [Route]
    # @param params [Hash]
    # @return [String]
    def generate_path_from_route(route, params = {})
      route.generate_path(params)
    end

    # Clear all routes and caches.
    #
    # @return [void]
    def clear!
      @routes.clear
      @named_routes.clear
      @recognition_cache.clear
      @cache_hits = 0
      @cache_misses = 0
      @radix_tree = RadixTree.new
    end

    # @return [Integer] number of routes
    def size
      @routes.size
    end

    # @return [Boolean]
    def empty?
      @routes.empty?
    end

    # Recognition cache statistics.
    #
    # @return [Hash] { hits:, misses:, hit_rate:, size: }
    def cache_stats
      total_lookups = @cache_hits + @cache_misses
      {
        hits: @cache_hits,
        misses: @cache_misses,
        hit_rate: total_lookups.zero? ? 0.0 : (@cache_hits.to_f / total_lookups * 100.0),
        size: @recognition_cache.size
      }
    end

    # Enumerate routes.
    #
    # @yield [route]
    # @return [Enumerator, self]
    def each(&block)
      return enum_for(:each) unless block
      @routes.each(&block)
      self
    end

    # Test membership.
    #
    # @param route [Route]
    # @return [Boolean]
    def include?(route)
      @routes.include?(route)
    end

    private

    # Cache insertion with simple segment eviction (25% oldest).
    #
    # @param cache_key [String]
    # @param entry [Hash]
    # @return [void]
    def insert_cache_entry(cache_key, entry)
      if @recognition_cache.size >= @recognition_cache_max
        @recognition_cache.keys.first(@recognition_cache_max / 4).each { |evict_key| @recognition_cache.delete(evict_key) }
      end
      @recognition_cache[cache_key] = entry
    end

    # Merge query parameters (if any) from full path into param hash.
    #
    # @param route_obj [Route]
    # @param full_path [String]
    # @param param_hash [Hash]
    # @return [void]
    def merge_query_params(route_obj, full_path, param_hash)
      return unless full_path.to_s.include?('?')
      if route_obj.respond_to?(:parse_query_params)
        qp = route_obj.parse_query_params(full_path)
        param_hash.merge!(qp) if qp
      elsif route_obj.respond_to?(:query_params)
        qp = route_obj.query_params(full_path)
        param_hash.merge!(qp) if qp
      end
    end

    # Obtain a pooled Hash for temporary params (not currently used).
    #
    # @return [Hash]
    def get_thread_local_params
      thread_params = Thread.current[:ruby_routes_params_pool] ||= []
      thread_params.empty? ? {} : thread_params.pop.clear
    end

    # Return a params Hash to the pool.
    #
    # @param params [Hash]
    # @return [void]
    def return_params_to_pool(params)
      params.clear
      thread_pool = Thread.current[:ruby_routes_params_pool] ||= []
      thread_pool << params if thread_pool.size < 10 # Limit pool size
    end
  end
end
