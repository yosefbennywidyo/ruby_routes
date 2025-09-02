# frozen_string_literal: true

require_relative 'route/small_lru'
require_relative 'segment'
require_relative 'utility/path_utility'
require_relative 'utility/method_utility'
require_relative 'node'
require_relative 'radix_tree/inserter'
require_relative 'radix_tree/finder'

module RubyRoutes
  # RadixTree
  #
  # Compact routing trie supporting:
  # - Static segments  (/users)
  # - Dynamic segments (/users/:id)
  # - Wildcard splat   (/assets/*path)
  #
  # Design / Behavior:
  # - Traversal keeps track of the deepest valid endpoint encountered
  #   (best_match_node) so that if a later branch fails, we can still
  #   return a shorter matching route.
  # - Dynamic and wildcard captures are written directly into the caller
  #   supplied params Hash (or a fresh one) to avoid intermediate objects.
  # - A very small manual LRU (Hash + order Array) caches the result of
  #   splitting raw paths into their segment arrays.
  #
  # Matching Precedence:
  #   static > dynamic > wildcard
  #
  # Thread Safety:
  # - Not thread‑safe for mutation (intended for boot‑time construction).
  #   Safe for concurrent reads after routes are added.
  #
  # @api internal
  class RadixTree
    include RubyRoutes::Utility::PathUtility
    include RubyRoutes::Utility::MethodUtility
    include Inserter
    include Finder

    class << self
      # Backwards DSL convenience: RadixTree.new(args) → Route
      def new(*args, &block)
        if args.any?
          RubyRoutes::Route.new(*args, &block)
        else
          super()
        end
      end
    end

    # Initialize empty tree and split cache.
    def initialize
      @root          = Node.new
      @split_cache        = RubyRoutes::Route::SmallLru.new(2048)
      @split_cache_max    = 2048
      @split_cache_order  = []
      @empty_segment_list = [].freeze
    end

    # Add a route to the tree (delegates insertion logic).
    #
    # @param raw_path [String]
    # @param http_methods [Array<String,Symbol>]
    # @param route_handler [Object]
    # @return [Object] route_handler
    def add(raw_path, http_methods, route_handler)
      normalized_path    = normalize_path(raw_path)
      normalized_methods = http_methods.map { |m| normalize_http_method(m) }
      insert_route(normalized_path, normalized_methods, route_handler)
      route_handler
    end

    # Public find delegates to Finder#find (now simplified on this class).
    def find(request_path_input, request_method_input, params_out = {})
      super
    end

    private

    # Split path with small manual LRU cache.
    #
    # @param raw_path [String]
    # @return [Array<String>]
    def split_path_cached(raw_path)
      return @empty_segment_list if raw_path == '/'

      cached = @split_cache.get(raw_path)
      return cached if cached

      segments = split_path(raw_path)
      @split_cache.set(raw_path, segments)
      segments
    end
  end
end
