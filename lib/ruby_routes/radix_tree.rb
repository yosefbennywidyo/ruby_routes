# frozen_string_literal: true

require_relative 'route/small_lru'
require_relative 'segment'
require_relative 'utility/path_utility'
require_relative 'utility/method_utility'
require_relative 'node'
require_relative 'radix_tree/inserter'
require_relative 'radix_tree/finder'

module RubyRoutes
  class RadixTree
    include RubyRoutes::Utility::PathUtility
    include RubyRoutes::Utility::MethodUtility
    include RubyRoutes::RadixTree::Inserter
    include RubyRoutes::RadixTree::Finder

    class << self
      # Allow RadixTree.new(path, options...) to act as a convenience factory
      def new(*args, &block)
        if args.any?
          RubyRoutes::Route.new(*args, &block)
        else
          super()
        end
      end
    end

    def initialize
      @root = Node.new
      @split_cache = RubyRoutes::Route::SmallLru.new(RubyRoutes::Constant::CACHE_SIZE)
      @split_cache_max = RubyRoutes::Constant::CACHE_SIZE      # larger cache for better hit rates
      @empty_segments = [].freeze  # reuse for root path
    end

    def add(path, methods, handler)
      insert_route(path, methods, handler)
    end

    private

    # Cached path splitting with optimized common cases
    def split_path_cached(path)
      @split_cache.get(path) || @split_cache.set(path, split_path(path))
    end
  end
end
