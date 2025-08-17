module RubyRoutes
  module LruStrategies
    class MissStrategy
      def call(lru, _key)
        lru.increment_misses
        nil
      end
    end
  end
end
