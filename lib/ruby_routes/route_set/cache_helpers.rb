# frozen_string_literal: true

require_relative '../route/small_lru'

module RubyRoutes
  class RouteSet
    # CacheHelpers: extracted cache, request-key, and eviction logic to reduce
    # the size of the main RouteSet class.
    #
    # This module provides methods for managing caches, request keys, and
    # implementing eviction policies for route recognition.
    module CacheHelpers

      attr_reader :named_routes, :small_lru
      # Recognition cache statistics.
      #
      # @return [Hash] A hash containing:
      #   - `:hits` [Integer] The number of cache hits.
      #   - `:misses` [Integer] The number of cache misses.
      #   - `:hit_rate` [Float] The cache hit rate as a percentage.
      #   - `:size` [Integer] The current size of the recognition cache.
      def cache_stats
        total_requests = @small_lru.hits + @small_lru.misses
        {
          hits: @small_lru.hits,
          misses: @small_lru.misses,
          hit_rate: total_requests.zero? ? 0.0 : (@small_lru.hits.to_f / total_requests * 100.0),
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
        @recognition_cache_max = RubyRoutes::Constant::CACHE_SIZE
        @small_lru = RubyRoutes::Route::SmallLru.new(RubyRoutes::Constant::CACHE_SIZE)
        @gen_cache = RubyRoutes::Route::SmallLru.new(RubyRoutes::Constant::CACHE_SIZE)
        @query_cache = RubyRoutes::Route::SmallLru.new(RubyRoutes::Constant::CACHE_SIZE)
        @cache_mutex = Mutex.new
      end

      # Fetch cached recognition entry while updating hit counter.
      #
      # @param lookup_key [String] The cache lookup key.
      # @return [Hash, nil] The cached recognition entry, or `nil` if not found.
      def fetch_cached_recognition(lookup_key)
        @cache_mutex.synchronize do
          if (cached_result = @recognition_cache[lookup_key])
            @small_lru.increment_hits
            return cached_result
          end

          @small_lru.increment_misses
          nil
        end
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
        @cache_mutex.synchronize do
          if @recognition_cache.size >= @recognition_cache_max
            # Calculate how many to keep (3/4 of max, rounded down)
            keep_count = (@recognition_cache_max * 3 / 4).to_i

            # Get the keys to keep (newest 75%, assuming insertion order)
            keys_to_keep = @recognition_cache.keys.last(keep_count)

            # Get the entries to keep
            entries_to_keep = @recognition_cache.slice(*keys_to_keep)

            # Clear the entire cache (evicts the oldest 25%)
            @recognition_cache.clear

            # Re-add the kept entries (3/4)
            @recognition_cache.merge!(entries_to_keep)
          end
          @recognition_cache[cache_key] = entry
        end
      end
    end
  end
end
