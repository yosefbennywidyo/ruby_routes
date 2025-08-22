module RubyRoutes
  class Route
    # small LRU used for path generation cache
    class SmallLru
      attr_reader :hits, :misses, :evictions

      # larger default to reduce eviction likelihood in benchmarks
      def initialize(max_size = 1024)
        @max_size = max_size
        @h = {}
        @hits = 0
        @misses = 0
        @evictions = 0

        @hit_strategy = RubyRoutes::Constant::LRU_HIT_STRATEGY
        @miss_strategy = RubyRoutes::Constant::LRU_MISS_STRATEGY
      end

      def get(key)
        strategy = @h.key?(key) ? @hit_strategy : @miss_strategy
        strategy.call(self, key)
      end

      def set(key, val)
        @h.delete(key) if @h.key?(key)
        @h[key] = val
        if @h.size > @max_size
          @h.shift
          @evictions += 1
        end
        val
      end

      def size
        @h.size
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
