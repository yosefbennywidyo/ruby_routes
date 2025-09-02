# frozen_string_literal: true

require 'rack/utils'

module RubyRoutes
  class Route
    # QueryHelpers: encapsulate query parsing/caching for Route instances.
    #
    # This module provides methods for parsing query parameters from a URL path
    # and caching the results for improved performance. It includes a wrapper
    # for cached parsing and a low-level implementation with an LRU cache.
    #
    # Provides:
    # - `parse_query_params(path)` -> Hash (public): Cached parsing wrapper.
    # - `query_params_fast(path)` -> Hash (public): Low-level parsing with LRU caching.
    module QueryHelpers
      # Parse query params (wrapper for internal caching).
      #
      # This method parses the query parameters from the given path and caches
      # the result for future lookups. It is a wrapper around the low-level
      # `query_params_fast` method.
      #
      # @param path [String] The URL path containing the query string.
      # @return [Hash] A hash of parsed query parameters.
      def parse_query_params(path)
        query_params_fast(path)
      end
      alias query_params parse_query_params

      # Query param parsing with simple LRU caching.
      #
      # This method parses the query parameters from the given path and caches
      # the result using a Least Recently Used (LRU) cache. If the query string
      # is already cached, the cached result is returned.
      #
      # @param path [String] The URL path containing the query string.
      # @return [Hash] A hash of parsed query parameters, or an empty hash if
      #   the path does not contain a valid query string.
      def query_params_fast(path)
        query_index = path.index('?')
        return RubyRoutes::Constant::EMPTY_HASH unless query_index

        query_part = path[(query_index + 1)..]
        return RubyRoutes::Constant::EMPTY_HASH if query_part.empty? || query_part.match?(/^\?+$/)

        if (cached_result = @cache_mutex.synchronize { @query_cache.get(query_part) })
          return cached_result
        end

        parsed_result = Rack::Utils.parse_query(query_part)
        @cache_mutex.synchronize { @query_cache.set(query_part, parsed_result) }
        parsed_result
      end
    end
  end
end
