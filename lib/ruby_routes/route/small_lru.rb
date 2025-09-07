# frozen_string_literal: true

#
# RubyRoutes::Route::SmallLru
#
# A tiny fixed‑capacity Least Recently Used (LRU) cache optimized for:
# - Very small memory footprint
# - Low per‑operation overhead
# - Predictable eviction (oldest key removed when capacity exceeded)
#
# Implementation notes:
# - Backed by a Ruby Hash (insertion order preserves LRU ordering when we reinsert on hit)
# - get promotes an entry by deleting + reinserting (handled by hit strategy)
# - External pluggable strategies supply side effects for hit / miss (counters, promotions)
# - Eviction uses Hash#shift (O(1) for Ruby >= 2.5)
#
# Thread safety: NOT thread‑safe. Wrap with a Mutex externally if sharing across threads.
#
# Public API surface kept intentionally small for hot path use in routing / path caching.
#
module RubyRoutes
  class Route
    # SmallLru
    # @!visibility public
    class SmallLru
      # @return [Integer] maximum number of entries retained
      # @return [Integer] number of cache hits
      # @return [Integer] number of cache misses
      # @return [Integer] number of evictions (when capacity exceeded)
      attr_reader :max_size, :hits, :misses, :evictions, :hash

      # @param max_size [Integer] positive maximum size
      # @raise [ArgumentError] if max_size < 1
      def initialize(max_size = 1024)
        max = Integer(max_size)
        raise ArgumentError, 'max_size must be >= 1' if max < 1

        @max_size  = max
        @hash      = {} # { key => value } (insertion order = LRU order)
        @hits      = 0
        @misses    = 0
        @evictions = 0
        # Strategy objects must respond_to?(:call). They receive (lru, key) or (lru, key, value).
        @hit_strategy  = RubyRoutes::Constant::LRU_HIT_STRATEGY
        @miss_strategy = RubyRoutes::Constant::LRU_MISS_STRATEGY
      end

      # Fetch a cached value.
      #
      # On hit:
      # - Strategy updates hit count and reorders key (strategy expected to call increment_hits + promote)
      # On miss:
      # - Strategy updates miss count (strategy expected to call increment_misses)
      #
      # @param key [Object]
      # @return [Object, nil] cached value or nil
      def get(key)
        lookup_strategy = @hash.key?(key) ? @hit_strategy : @miss_strategy
        lookup_strategy.call(self, key)
      end

      # Insert or update an entry.
      # Re-inserts key to become most recently used.
      # Evicts least recently used (Hash#shift) if capacity exceeded.
      #
      # @param key [Object]
      # @param value [Object]
      # @return [Object] value
      def set(key, value)
        @hash.delete(key) if @hash.key?(key) # promote existing
        @hash[key] = value
        if @hash.size > @max_size
          @hash.shift
          @evictions += 1
        end
        value
      end

      # @return [Integer] current number of entries
      def size
        @hash.size
      end

      # @return [Boolean]
      def empty?
        @hash.empty?
      end

      # @return [Array<Object>] keys in LRU order (oldest first)
      def keys
        @hash.keys
      end

      # Check if a key exists in the cache.
      #
      # @param key [Object] The key to check.
      # @return [Boolean] True if the key exists, false otherwise.
      def has_key?(key)
        @hash.key?(key)
      end

      # Hash-like access for reading (delegates to get).
      #
      # @param key [Object] The key to retrieve.
      # @return [Object, nil] The cached value or nil.
      def [](key)
        get(key)
      end

      # Include matcher (checks for key-value pair).
      #
      # @param pair [Hash] A hash with a single key-value pair (e.g., { 'key' => 'value' }).
      # @return [Boolean] True if the pair exists in the cache, false otherwise.
      def include?(pair)
        return false unless pair.is_a?(Hash) && pair.size == 1

        key, value = pair.first
        @hash[key] == value
      end

      # Hash-like access for writing (delegates to set).
      #
      # @param key [Object] The key to set.
      # @param value [Object] The value to cache.
      # @return [Object] The value.
      def []=(key, value)
        set(key, value)
      end

      # Debug / spec helper (avoid exposing internal Hash directly).
      # @return [Hash] shallow copy of internal store
      def inspect_hash
        @hash.dup
      end

      # Increment hit counter (intended for strategy objects).
      # @return [void]
      def increment_hits
        @hits += 1
      end

      # Increment miss counter (intended for strategy objects).
      # @return [void]
      def increment_misses
        @misses += 1
      end

      def clear_counters!
        @hits = 0
        @misses = 0
        @evictions = 0
      end

      # Internal helper used by hit strategy to promote key.
      # @param key [Object]
      # @return [void]
      def promote(key)
        val = @hash.delete(key)
        @hash[key] = val if val
      end
    end
  end
end
