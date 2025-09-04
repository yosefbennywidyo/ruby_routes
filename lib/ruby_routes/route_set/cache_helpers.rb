# frozen_string_literal: true

module RubyRoutes
  class RouteSet
    # CacheHelpers: extracted cache, request-key, and eviction logic to reduce
    # the size of the main RouteSet class.
    #
    # This module provides methods for managing caches, request keys, and
    # implementing eviction policies for route recognition.
    module CacheHelpers
      # Recognition cache statistics.
      #
      # @return [Hash] A hash containing:
      #   - `:hits` [Integer] The number of cache hits.
      #   - `:misses` [Integer] The number of cache misses.
      #   - `:hit_rate` [Float] The cache hit rate as a percentage.
      #   - `:size` [Integer] The current size of the recognition cache.
      def cache_stats
        total_requests = @cache_hits + @cache_misses
        {
          hits: @cache_hits,
          misses: @cache_misses,
          hit_rate: total_requests.zero? ? 0.0 : (@cache_hits.to_f / total_requests * 100.0),
          size: @recognition_cache.size
        }
      end

      private

      # Set up caches and request-key ring.
      #
      # Initializes the internal data structures for managing routes, named routes,
      # recognition cache, and request-key ring buffer.
      #
      # @return [void]
      def setup_caches
        @routes = []
        @named_routes = {}
        @recognition_cache = {}
        @recognition_cache_max = 2048
        @cache_hits = 0
        @cache_misses = 0
      end

      # Fetch cached recognition entry while updating hit counter.
      #
      # @param lookup_key [String] The cache lookup key.
      # @return [Hash, nil] The cached recognition entry, or `nil` if not found.
      def fetch_cached_recognition(lookup_key)
        if (cached_result = @recognition_cache[lookup_key])
          @cache_hits += 1
          return cached_result
        end
        @cache_misses += 1
        nil
      end

      # Cache insertion with simple segment eviction (25% oldest).
      #
      # Adds a new entry to the recognition cache, evicting the oldest 25% of entries
      # if the cache exceeds its maximum size.
      #
      # @param cache_key [String] The cache key.
      # @param entry [Hash] The cache entry.
      # @return [void]
      def insert_cache_entry(cache_key, entry)
        @cache_mutex ||= Mutex.new
        @cache_mutex.synchronize do
          if @recognition_cache.size >= @recognition_cache_max
            @recognition_cache.keys.first(@recognition_cache_max / 4).each do |evict_key|
              @recognition_cache.delete(evict_key)
            end
          end
          @recognition_cache[cache_key] = entry
        end
      end
    end
  end
end
