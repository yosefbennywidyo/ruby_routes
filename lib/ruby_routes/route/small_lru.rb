module RubyRoutes
  class Route
    # SmallLru
    #
    # A tiny, allocation‑lean Least Recently Used (approximate) cache used
    # for per‑route path generation and query parsing. It relies on Ruby's
    # ordered Hash to keep insertion order; a hit promotes an entry by
    # deleting and reinserting the key (via the hit strategy).
    #
    # Eviction policy:
    # - On insert (set) if size > max_size the oldest (Hash#shift) entry
    #   is removed (simple LRU approximation).
    # - Hit strategy reorders the key to behave like MRU promotion.
    #
    # Strategy objects (see LruStrategies::HitStrategy / MissStrategy) are
    # injected via RubyRoutes::Constant allowing future policy changes
    # without touching this class.
    #
    # Thread safety: NOT thread‑safe. Intended for per‑route instances
    # accessed mostly on a single thread (e.g., request thread).
    #
    # @api internal
    class SmallLru
      # @return [Integer] number of successful cache lookups
      attr_reader :hits
      # @return [Integer] number of failed cache lookups
      attr_reader :misses
      # @return [Integer] number of evicted entries
      attr_reader :evictions

      # @param max_size [Integer] maximum number of entries to retain
      def initialize(max_size = 1024)
        max = Integer(max_size)
        raise ArgumentError, "max_size must be >= 1" if max < 1
        @max_size      = max
        @hash          = {}   # internal ordered storage
        @hits          = 0
        @misses        = 0
        @evictions     = 0
        @hit_strategy  = RubyRoutes::Constant::LRU_HIT_STRATEGY
        @miss_strategy = RubyRoutes::Constant::LRU_MISS_STRATEGY
      end

      def get(key)
        lookup_strategy = @hash.key?(key) ? @hit_strategy : @miss_strategy
        lookup_strategy.call(self, key)
      end

      def set(key, value)
        @hash.delete(key) if @hash.key?(key)
        @hash[key] = value
        if @hash.size > @max_size
          @hash.shift
          @evictions += 1
        end
        value
      end

      def size
        @hash.size
      end

      def increment_hits
        @hits += 1
      end

      def increment_misses
        @misses += 1
      end
    end
  end
end
