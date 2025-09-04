# frozen_string_literal: true

require_relative 'path_generation'
require_relative 'warning_helpers'
require_relative 'constraint_validator'

module RubyRoutes
  class Route
    # ParamSupport: helpers for parameter merging and cache key generation.
    #
    # This module provides methods for efficiently merging parameters, generating
    # cache keys, and extracting parameters from request paths. It uses thread-local
    # hashes for performance and includes a 2-slot LRU cache for param key generation.
    #
    # Thread-safety: Thread-local storage is used to avoid allocation and cross-thread mutation.
    module ParamSupport
      include RubyRoutes::Route::WarningHelpers

      private

      # Merge incoming params with route defaults.
      #
      # This method merges user-provided parameters with route defaults and returns
      # a thread-local hash for performance.
      #
      # @param params [Hash] The user-provided parameters.
      # @return [Hash] The merged parameters.
      def build_merged_params(params)
        return @defaults if params.nil? || params.empty?

        merged_hash = acquire_merge_hash
        merge_defaults_into(merged_hash)
        merge_user_params_into(merged_hash, params)
        merged_hash
      end

      # Acquire a thread-local hash for merging.
      #
      # @return [Hash] A cleared thread-local hash for merging.
      def acquire_merge_hash
        merged_hash = Thread.current[:ruby_routes_merge_hash] ||= {}
        merged_hash.clear
        merged_hash
      end

      # Merge defaults into the hash.
      #
      # @param merged_hash [Hash] The hash to merge defaults into.
      # @return [void]
      def merge_defaults_into(merged_hash)
        @defaults.each { |key, value| merged_hash[key] = value } unless @defaults.empty?
      end

      # Merge user params into the hash.
      #
      # This method converts keys to strings and skips nil values.
      #
      # @param merged_hash [Hash] The hash to merge user parameters into.
      # @param params [Hash] The user-provided parameters.
      # @return [void]
      def merge_user_params_into(merged_hash, params)
        params.each do |key, value|
          next if value.nil?

          merged_hash[key.is_a?(String) ? key : key.to_s] = value
        end
      end

      # Build a frozen cache key for the merged params and update the 2-slot cache.
      #
      # @param merged_params [Hash] The merged parameters.
      # @return [String] The frozen cache key.
      def build_param_cache_key(merged_params)
        param_cache_key = cache_key_for_params(@required_params, merged_params)
        cache_key_hash = param_cache_key.hash

        if (cache_slot = @param_key_slots[0])[0] == cache_key_hash && cache_slot[1] == param_cache_key
          return cache_slot[1]
        elsif (cache_slot = @param_key_slots[1])[0] == cache_key_hash && cache_slot[1] == param_cache_key
          return cache_slot[1]
        end

        store_param_key_slot(cache_key_hash, param_cache_key)
      end

      # Store the param cache key in the 2-slot LRU.
      #
      # @param cache_key_hash [Integer] The hash of the cache key.
      # @param param_cache_key [String] The cache key to store.
      # @return [String] The stored cache key.
      def store_param_key_slot(cache_key_hash, param_cache_key)
        if @param_key_slots[0][0].nil?
          @param_key_slots[0] = [cache_key_hash, param_cache_key]
        elsif @param_key_slots[1][0].nil?
          @param_key_slots[1] = [cache_key_hash, param_cache_key]
        else
          @param_key_slots[0] = @param_key_slots[1]
          @param_key_slots[1] = [cache_key_hash, param_cache_key]
        end
        param_cache_key
      end

      # Extract parameters from a request path (and optionally pre-parsed query).
      #
      # @param request_path [String] The request path.
      # @param parsed_qp [Hash, nil] Pre-parsed query parameters to merge (optional).
      # @return [Hash] The extracted parameters, with defaults merged in.
      def extract_params(request_path, parsed_qp = nil)
        extracted_path_params = extract_path_params_fast(request_path)
        return RubyRoutes::Constant::EMPTY_HASH unless extracted_path_params

        build_params_hash(extracted_path_params, request_path, parsed_qp)
      end

      # Build full params hash (path + query + defaults + constraints).
      #
      # @param path_params [Hash] The extracted path parameters.
      # @param request_path [String] The request path.
      # @param parsed_qp [Hash, nil] Pre-parsed query parameters.
      # @return [Hash] The full parameters hash.
      def build_params_hash(path_params, request_path, parsed_qp)
        params_hash = get_thread_local_hash
        params_hash.update(path_params)

        merge_query_params_into_hash(params_hash, request_path, parsed_qp)

        merge_defaults_fast(params_hash) unless @defaults.empty?
        validate_constraints_fast!(params_hash) unless @constraints.empty?
        params_hash.dup
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

      # Acquire thread-local hash.
      #
      # @return [Hash]
      def acquire_thread_local_hash
        pool = Thread.current[:ruby_routes_hash_pool] ||= []
        return {} if pool.empty?

        hash = pool.pop
        hash.clear
        hash
      end

      alias get_thread_local_hash acquire_thread_local_hash # backward compatibility if referenced elsewhere

      # Merge query params into the hash.
      #
      # @param params_hash [Hash] The hash to merge query parameters into.
      # @param request_path [String] The request path.
      # @param parsed_qp [Hash, nil] Pre-parsed query parameters.
      # @return [void]
      def merge_query_params_into_hash(params_hash, request_path, parsed_qp)
        if parsed_qp
          params_hash.merge!(parsed_qp)
        elsif request_path.include?('?')
          query_params = query_params_fast(request_path)
          params_hash.merge!(query_params) unless query_params.empty?
        end
      end

      # Merge defaults where absent.
      #
      # @param result [Hash] The hash to merge defaults into.
      # @return [void]
      def merge_defaults_fast(result)
        @defaults.each { |key, value| result[key] = value unless result.key?(key) }
      end

      # Retrieve query params from route object via supported method.
      #
      # @param route_obj [Route] The route object.
      # @param full_path [String] The full path containing the query string.
      # @return [Hash, nil] The query parameters, or `nil` if none are found.
      def retrieve_query_params(route_obj, full_path)
        if route_obj.respond_to?(:parse_query_params)
          route_obj.parse_query_params(full_path)
        elsif route_obj.respond_to?(:query_params)
          route_obj.query_params(full_path)
        end
      end
    end
  end
end
