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
        @request_key_pool = {}
        @request_key_ring = Array.new(RubyRoutes::Constant::REQUEST_KEY_CAPACITY)
        @entry_count = 0
        @ring_index = 0
      end

      # Fetch (or build) a composite request cache key with ring-buffer eviction.
      #
      # Ensures consistent use of frozen method/path keys to avoid mixed key space bugs.
      #
      # @param http_method [String, Symbol] The HTTP method (e.g., `:get`, `:post`).
      # @param request_path [String] The request path.
      # @return [String] The composite request key.
      def fetch_request_key(http_method, request_path)
        method_key, path_key = normalize_keys(http_method, request_path)
        composite_key = build_composite_key(method_key, path_key)

        return composite_key if handle_cache_hit(method_key, path_key, composite_key)

        handle_cache_miss(method_key, path_key, composite_key)
        composite_key
      end

      # Normalize keys.
      #
      # Converts the HTTP method and request path into frozen strings for consistent
      # key usage.
      #
      # @param http_method [String, Symbol] The HTTP method.
      # @param request_path [String] The request path.
      # @return [Array<String>] An array containing the normalized method and path keys.
      def normalize_keys(http_method, request_path)
        method_key = http_method.is_a?(String) ? http_method.upcase.freeze : http_method.to_s.upcase.freeze
        path_key = request_path.is_a?(String) ? request_path.freeze : request_path.to_s.freeze
        [method_key, path_key]
      end

      # Build composite key.
      #
      # Combines the HTTP method and path into a single composite key.
      #
      # @param method_key [String] The normalized HTTP method key.
      # @param path_key [String] The normalized path key.
      # @return [String] The composite key.
      def build_composite_key(method_key, path_key)
        "#{method_key}:#{path_key}".freeze
      end

      # Handle cache hit.
      #
      # Checks if the composite key already exists in the request key pool.
      #
      # @param method_key [String] The normalized HTTP method key.
      # @param path_key [String] The normalized path key.
      # @param _composite_key [String] The composite key (unused).
      # @return [Boolean] `true` if the key exists, `false` otherwise.
      def handle_cache_hit(method_key, path_key, _composite_key)
        return true if @request_key_pool[method_key]&.key?(path_key)

        false
      end

      # Handle cache miss.
      #
      # Adds the composite key to the request key pool and manages the ring buffer
      # for eviction.
      #
      # @param method_key [String] The normalized HTTP method key.
      # @param path_key [String] The normalized path key.
      # @param composite_key [String] The composite key.
      # @return [void]
      def handle_cache_miss(method_key, path_key, composite_key)
        @request_key_pool[method_key][path_key] = composite_key if @request_key_pool[method_key]
        @request_key_pool[method_key] = { path_key => composite_key } unless @request_key_pool[method_key]

        if @entry_count < RubyRoutes::Constant::REQUEST_KEY_CAPACITY
          @request_key_ring[@entry_count] = [method_key, path_key]
          @entry_count += 1
        else
          evict_old_entry(method_key, path_key)
        end
      end

      # Evict old entry.
      #
      # Removes the oldest entry from the request key pool and updates the ring buffer.
      #
      # @param method_key [String] The normalized HTTP method key.
      # @param path_key [String] The normalized path key.
      # @return [void]
      def evict_old_entry(method_key, path_key)
        evict_method, evict_path = @request_key_ring[@ring_index]
        if (evict_bucket = @request_key_pool[evict_method]) && evict_bucket.delete(evict_path) && evict_bucket.empty?
          @request_key_pool.delete(evict_method)
        end
        @request_key_ring[@ring_index] = [method_key, path_key]
        @ring_index += 1
        @ring_index = 0 if @ring_index == RubyRoutes::Constant::REQUEST_KEY_CAPACITY
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
