# frozen_string_literal: true

require_relative 'route/small_lru'
require_relative 'constant'

module RubyRoutes
  # CacheSetup: shared module for initializing caches across Route and RouteSet.
  #
  # This module provides common cache setup methods to reduce duplication
  # and ensure consistency in cache initialization.
  module CacheSetup
    attr_reader :named_routes, :small_lru, :gen_cache, :query_cache, :validation_cache,
                :cache_hits, :cache_misses

    # Initialize recognition caches for RouteSet.
    #
    # @return [void]
    def setup_caches
      @routes                 = []
      @named_routes           = {}
      @recognition_cache      = {}
      @cache_mutex            = Mutex.new
      @cache_hits             = 0
      @cache_misses           = 0
      @recognition_cache_max  = RubyRoutes::Constant::CACHE_SIZE
      @small_lru              = RubyRoutes::Route::SmallLru.new(RubyRoutes::Constant::CACHE_SIZE)
      @gen_cache              = RubyRoutes::Route::SmallLru.new(RubyRoutes::Constant::CACHE_SIZE)
      @query_cache            = RubyRoutes::Route::SmallLru.new(RubyRoutes::Constant::CACHE_SIZE)
      @validation_cache       = RubyRoutes::Route::SmallLru.new(RubyRoutes::Constant::CACHE_SIZE)
    end
  end
end
