# frozen_string_literal: true

require_relative 'strategies'
require_relative 'utility/key_builder_utility'
require_relative 'utility/method_utility'
require_relative 'route_set/cache_helpers'
require_relative 'route_set/collection_helpers'
require_relative 'route/param_support'
require_relative 'route/path_generation'

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
  # - Delegate structural path matching to a configurable strategy.
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
    include RubyRoutes::Route::PathGeneration
    include RubyRoutes::RouteSet::CollectionHelpers

    # Initialize empty collection and caches.
    #
    # @param strategy [Class] The matching strategy to use.
    # @return [void]
    def initialize(strategy: Strategies::HybridStrategy)
      setup_caches
      setup_strategy(strategy)
    end

    # Recognize a request (method + path) returning route + params.
    #
    # @param http_method [String, Symbol] The HTTP method (e.g., "GET").
    # @param path [String] The request path.
    # @return [Hash, nil] A hash containing the matched route and parameters, or `nil` if no match is found.
    def match(http_method, path)
      normalized_method = normalize_http_method(http_method)
      lookup_key = cache_key_for_request(normalized_method, path.to_s)

      if (cached_result = fetch_cached_recognition(lookup_key))
        return cached_result
      end

      result = perform_match(normalized_method, path.to_s)
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
      generate_path_from_route(find_named_route(name), params)
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

    # Set up the matching strategy.
    #
    # @param strategy [Class] The matching strategy class.
    # @return [void]
    def setup_strategy(strategy)
      @strategy_class = strategy
      @strategy = @strategy_class.new
    end

    # Perform the route matching process.
    #
    # @param normalized_method [String] The normalized HTTP method.
    # @param raw_path [String] The raw request path.
    # @return [Hash, nil] A hash containing the matched route and parameters, or `nil` if no match is found.
    def perform_match(normalized_method, raw_path)
      path_without_query = raw_path.split('?', 2).first
      matched_route, path_params = @strategy.find(path_without_query, normalized_method)
      return nil unless matched_route

      final_params = build_final_params(matched_route, path_params, raw_path)
      build_match_result(matched_route, final_params)
    end

    # Build the final parameters hash by merging path, query, and default params.
    #
    # @param matched_route [Route] The matched route.
    # @param path_params [Hash] The parameters extracted from the path.
    # @param raw_path [String] The full request path including query string.
    # @return [Hash] The final, merged parameters hash.
    def build_final_params(matched_route, path_params, raw_path)
      # Start with a mutable copy of path_params or a new hash.
      final_params = path_params&.frozen? ? path_params.dup : (path_params || {})

      # Merge query parameters if any exist.
      matched_route.merge_query_params_into_hash(final_params, raw_path, nil)

      # Merge default parameters, which have the lowest precedence.
      if matched_route.respond_to?(:defaults) && (defaults = matched_route.defaults)
        defaults.each { |key, value| final_params[key] = value unless final_params.key?(key) }
      end

      final_params
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
  end
end
