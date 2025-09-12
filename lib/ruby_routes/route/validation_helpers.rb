# frozen_string_literal: true

require_relative 'check_helpers'

module RubyRoutes
  class Route
    # ValidationHelpers: extracted validation and defaults logic.
    #
    # This module provides methods for validating routes, required parameters,
    # and hash-form constraints. It also includes caching mechanisms for
    # validation results and utilities for managing hash pools.
    module ValidationHelpers
      include RubyRoutes::Route::CheckHelpers

      # Initialize validation result cache.
      #
      # This method initializes an LRU (Least Recently Used) cache for storing
      # validation results, with a maximum size of 64 entries.
      #
      # @return [void]
      def initialize_validation_cache
        @validation_cache = SmallLru.new(64)
      end

      # Validate fundamental route shape.
      #
      # This method ensures that the route has a valid controller, action, and
      # HTTP method. If any of these are invalid, an `InvalidRoute` exception
      # is raised.
      #
      # @raise [InvalidRoute] If the route is invalid.
      # @return [void]
      def validate_route!
        raise InvalidRoute, 'Controller is required' if @controller.nil?
        raise InvalidRoute, 'Action is required' if @action.nil?
        raise InvalidRoute, "Invalid HTTP method: #{@methods}" if @methods.empty?
      end

      # Validate required parameters once.
      #
      # This method validates that all required parameters are present and not
      # nil. It uses per-params caching to avoid re-validation for the same
      # frozen params.
      #
      # @param params [Hash] The parameters to validate.
      # @raise [RouteNotFound] If required parameters are missing or nil.
      # @return [void]
      def validate_required_once(params)
        return if @required_params.empty?

        cached_result = get_cached_validation(params)
        if cached_result
          missing, nils = cached_result
        else
          missing, nils = validate_required_params(params)
          cache_validation_result(params.freeze, [missing, nils])
        end

        raise RouteNotFound, "Missing params: #{missing.join(', ')}" unless missing.empty?
        raise RouteNotFound, "Missing or nil params: #{nils.join(', ')}" unless nils.empty?
      end

      # Validate required parameters.
      #
      # This method checks for missing or nil required parameters.
      #
      # @param params [Hash] The parameters to validate.
      # @return [Array<Array>] An array containing two arrays:
      #   - `missing` [Array<String>] The keys of missing parameters.
      #   - `nils` [Array<String>] The keys of parameters that are nil.
      def validate_required_params(params)
        return RubyRoutes::Constant::EMPTY_PAIR if @required_params.empty?
        params ||= {}

        missing = []
        nils = []
        @required_params.each do |required_key|
          process_required_key(required_key, params, missing, nils)
        end
        result = [missing, nils]
        cache_validation_result(params, result)
        result
      end

      # Per-key validation helper used by `validate_required_params`.
      #
      # This method checks if a specific required key is present and not nil.
      #
      # @param required_key [String] The required parameter key.
      # @param params [Hash] The parameters to validate.
      # @param missing [Array<String>] The array to store missing keys.
      # @param nils [Array<String>] The array to store keys with nil values.
      # @return [void]
      def process_required_key(required_key, params, missing, nils)
        if params.key?(required_key)
          nils << required_key if params[required_key].nil?
        else
          symbol_key = required_key.to_sym
          if params.key?(symbol_key)
            nils << required_key if params[symbol_key].nil?
          else
            missing << required_key
          end
        end
      end

      # Cache validation result.
      #
      # This method stores the validation result in the cache if the parameters
      # are frozen and the cache is not full.
      #
      # @param params [Hash] The parameters used for validation.
      # @param result [Object] The validation result to cache.
      # @return [void]
      def cache_validation_result(params, result)
        return unless params.frozen?
        return unless @validation_cache

        @cache_mutex.synchronize do
          @validation_cache.set(params.hash, result)
        end
      end
      #
      # @param params [Hash] The parameters used for validation.
      # @return [Object, nil] The cached validation result, or `nil` if not found.
      def get_cached_validation(params)
        return nil unless params && @validation_cache
        @cache_mutex.synchronize { @validation_cache.get(params.hash) }
      end

      # Return hash to pool.
      #
      # This method returns a hash to the thread-local hash pool for reuse.
      #
      # @param hash [Hash] The hash to return to the pool.
      # @return [void]
      def return_hash_to_pool(hash)
        pool = Thread.current[:ruby_routes_hash_pool] ||= []
        pool.push(hash) if pool.size < 5
      end
    end
  end
end
