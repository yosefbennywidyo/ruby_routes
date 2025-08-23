# frozen_string_literal: true

module RubyRoutes
  module LruStrategies
    # MissStrategy
    #
    # Implements the behavior executed when a key lookup in SmallLru
    # does not exist. It increments miss counters and returns nil.
    #
    # This object-oriented strategy form allows swapping behaviors
    # without adding conditionals in the hot LRU path.
    #
    # @example Basic usage (internal)
    #   lru = SmallLru.new
    #   strategy = RubyRoutes::LruStrategies::MissStrategy.new
    #   strategy.call(lru, :unknown) # => nil (and increments lru.misses)
    #
    # @api internal
    class MissStrategy
      # Execute miss handling.
      #
      # @param lru [SmallLru] the LRU cache instance
      # @param _key [Object] the missed key (unused)
      # @return [nil] always nil to signal absence
      def call(lru, _key)
        lru.increment_misses
        nil
      end
    end
  end
end
