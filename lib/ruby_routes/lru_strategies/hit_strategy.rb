module RubyRoutes
  module LruStrategies
    class HitStrategy
      def call(lru, key)
        lru.increment_hits
        h = lru.instance_variable_get(:@h)
        val = h.delete(key)
        h[key] = val
        val
      end
    end
  end
end
