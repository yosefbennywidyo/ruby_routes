# frozen_string_literal: true

module RubyRoutes
  module LruStrategies
    # HitStrategy
    #
    # Strategy object invoked when a lookup in SmallLru succeeds.
    # Responsibilities:
    # - Increment the hit counter.
    # - Reinsert the accessed key at the logical MRU position to
    #   approximate LRU behavior using simple Hash order.
    #
    # Isolation of this logic allows the hot path in SmallLru#get
    # to delegate without conditionals, and lets alternative
    # eviction / promotion policies be swapped in tests or future
    # tuning without rewriting cache code.
    #
    # @example (internal usage)
    #   lru = SmallLru.new
    #   RubyRoutes::LruStrategies::HitStrategy.new.call(lru, :k)
    #
    # @api internal
    class HitStrategy
      # Promote a key on cache hit.
      #
      # @param lru [SmallLru] the owning LRU cache
      # @param key [Object] the key that was found
      # @return [Object] the cached value
      def call(lru, key)
        lru.increment_hits
        # Internal storage name (@hash) is intentionally accessed reflectively
        # to keep strategy decoupled from public API surface.
        store = lru.hash
        value = store.delete(key)
        store[key] = value
        value
      end
    end
  end
end
