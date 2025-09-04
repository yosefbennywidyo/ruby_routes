# frozen_string_literal: true

require_relative 'radix_tree'
require_relative 'utility/key_builder_utility'
require_relative 'utility/method_utility'
require_relative 'route_set/cache_helpers'
require_relative 'route_set/collection_helpers'
require_relative 'route/param_support'

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
  # Thread Safety:
  # - RouteSet instances are not fully thread-safe for modifications.
  # - Build during boot/initialization, then use read-only per request.
  # - Global caches (via KeyBuilderUtility) are thread-safe for concurrent reads.
  # - Per-instance recognition cache is not protected (single-threaded usage assumed).
  #
  # @api public (primary integration surface)
  class RouteSet
    attr_reader :routes

    include RubyRoutes::Utility::KeyBuilderUtility
    include RubyRoutes::Utility::MethodUtility
    include RubyRoutes::RouteSet::CacheHelpers
    include RubyRoutes::Route::ParamSupport
    include RubyRoutes::RouteSet::CollectionHelpers

    # Initialize empty collection and caches.
    #
    # @return [void]
    def initialize
      setup_caches
      setup_radix_tree
    end

    # Recognize a request (method + path) returning route + params.
    #
    # @param http_method [String, Symbol] The HTTP method (e.g., "GET").
    # @param path [String] The request path.
    # @return [Hash, nil] A hash containing the matched route and parameters, or `nil` if no match is found.
    def match(http_method, path)
      normalized_method = normalize_method_for_match(http_method)
      raw_path = path.to_s
      lookup_key = cache_key_for_request(normalized_method, raw_path)

      if (cached_result = fetch_cached_recognition(lookup_key))
        return cached_result
      end

      result = perform_match(normalized_method, raw_path)
      insert_cache_entry(lookup_key, result) if result
      result
    end

    # Convenience alias for Rack‑style recognizer.
    #
    # @param path [String] The request path.
    # @param method [String, Symbol] The HTTP method (default: "GET").
    # @return [Hash, nil] A hash containing the matched route and parameters, or `nil` if no match is found.
    def recognize_path(path, method = 'GET')
      match(method, path)
    end

    # Generate path via named route.
    #
    # @param name [Symbol, String] The name of the route.
    # @param params [Hash] The parameters for path generation.
    # @return [String] The generated path.
    def generate_path(name, params = {})
      route = find_named_route(name)
      route.generate_path(params)
    end

    # Generate path from a direct route reference.
    #
    # @param route [Route] The route instance.
    # @param params [Hash] The parameters for path generation.
    # @return [String] The generated path.
    def generate_path_from_route(route, params = {})
      route.generate_path(params)
    end

    private

    # Set up the radix tree for structural path matching.
    #
    # @return [void]
    def setup_radix_tree
      @radix_tree = RadixTree.new
    end

    # Normalize the HTTP method for matching.
    #
    # @param http_method [String, Symbol] The HTTP method.
    # @return [String] The normalized HTTP method.
    def normalize_method_for_match(http_method)
      if http_method.is_a?(String) && normalize_http_method(http_method).equal?(http_method)
        http_method
      else
        normalize_http_method(http_method)
      end
    end

    # Perform the route matching process.
    #
    # @param normalized_method [String] The normalized HTTP method.
    # @param raw_path [String] The raw request path.
    # @return [Hash, nil] A hash containing the matched route and parameters, or `nil` if no match is found.
    def perform_match(normalized_method, raw_path)
      path_without_query, _query = raw_path.split('?', 2)
      matched_route, extracted_params = @radix_tree.find(path_without_query, normalized_method)
      return nil unless matched_route

      # Ensure we have a mutable hash for merging defaults / query params.
      if extracted_params.nil?
        extracted_params = {}
      elsif extracted_params.frozen?
        extracted_params = extracted_params.dup
      end

      merge_query_params(matched_route, raw_path, extracted_params)
      merge_defaults(matched_route, extracted_params)
      build_match_result(matched_route, extracted_params)
    end

    # Merge default parameters into the extracted parameters.
    #
    # @param matched_route [Route] The matched route.
    # @param extracted_params [Hash] The extracted parameters.
    # @return [void]
    def merge_defaults(matched_route, extracted_params)
      return unless matched_route.respond_to?(:defaults) && matched_route.defaults

      matched_route.defaults.each { |key, value| extracted_params[key] = value unless extracted_params.key?(key) }
    end

    # Build the match result hash.
    #
    # @param matched_route [Route] The matched route.
    # @param extracted_params [Hash] The extracted parameters.
    # @return [Hash] A hash containing the matched route, parameters, controller, and action.
    def build_match_result(matched_route, extracted_params)
      {
        route: matched_route,
        params: extracted_params,
        controller: matched_route.controller,
        action: matched_route.action
      }
    end

    # Obtain a pooled hash for temporary parameters.
    #
    # @return [Hash] A thread-local hash for temporary parameter storage.
    def thread_local_params
      thread_params = Thread.current[:ruby_routes_params_pool] ||= []
      thread_params.empty? ? {} : thread_params.pop.clear
    end

    # Return a parameters hash to the thread-local pool.
    #
    # @param params [Hash] The parameters hash to return.
    # @return [void]
    def return_params_to_pool(params)
      params.clear
      thread_pool = Thread.current[:ruby_routes_params_pool] ||= []
      thread_pool << params if thread_pool.size < 10 # Limit pool size
    end
  end
end
