# frozen_string_literal: true

require 'uri'
require 'timeout'
require 'rack'
require 'set'
require_relative 'constant'
require_relative 'node'
require_relative 'cache_setup'
require_relative 'route_set/cache_helpers'
require_relative 'route/small_lru'
require_relative 'utility/key_builder_utility'
require_relative 'utility/method_utility'
require_relative 'utility/path_utility'
require_relative 'utility/route_utility'
require_relative 'route/param_support'
require_relative 'segment'
require_relative 'route/path_builder'
require_relative 'route/constraint_validator'
require_relative 'route/check_helpers'
require_relative 'route/query_helpers'
require_relative 'route/validation_helpers'
require_relative 'route/segment_compiler'
require_relative 'route/path_generation'

module RubyRoutes
  # Route
  #
  # Immutable-ish representation of a single HTTP route plus optimized
  # helpers for:
  # - Path recognition (segment compilation + fast param extraction)
  # - Path generation (low‑allocation caching + param merging)
  # - Constraint validation (regexp / typed / hash rules)
  #
  # Performance Techniques:
  # - Precompiled segment descriptors (static / param / splat)
  # - Small LRU caches (path generation + query parsing)
  # - Thread‑local reusable Hashes / String buffers
  # - Minimal object allocation in hot paths
  #
  # Thread Safety:
  # - Instance is effectively read‑only after initialization.
  # - Internal caches (@query_cache, @gen_cache, @validation_cache) are protected
  #   by a mutex for safe concurrent access across multiple threads.
  # - Designed for "build during boot, read per request" usage pattern.
  #
  # Public API Surface (stable):
  # - #match?
  # - #extract_params
  # - #generate_path
  # - #named?
  # - #resource? / #collection?
  #
  # @api public
  class Route
    include ParamSupport
    include PathBuilder
    include RubyRoutes::Route::ConstraintValidator
    include RubyRoutes::Route::ValidationHelpers
    include RubyRoutes::Route::QueryHelpers
    include RubyRoutes::Route::PathGeneration
    include RubyRoutes::Route::SegmentCompiler
    include RubyRoutes::Utility::MethodUtility
    include RubyRoutes::Utility::PathUtility
    include RubyRoutes::Utility::KeyBuilderUtility
    include RubyRoutes::RouteSet::CacheHelpers
    include RubyRoutes::CacheSetup

    attr_reader :path, :methods, :controller, :action, :name, :constraints, :defaults

    public :extract_params, :parse_query_params, :query_params, :generate_path, :merge_query_params_into_hash

    # Create a new Route.
    #
    # @param path [String] The raw route path (may include `:params` or `*splat`).
    # @param options [Hash] The options for the route.
    # @option options [Symbol, String, Array<Symbol, String>] :via (:get) HTTP method(s).
    # @option options [String] :to The controller#action string.
    # @option options [String] :controller The controller name.
    # @option options [String] :action The action name.
    # @option options [String] :as The route name.
    # @option options [Hash] :constraints The route constraints.
    # @option options [Hash] :defaults The route defaults.
    def initialize(path, options = {})
      @options = options
      @path = normalize_path(path)
      @name = @options[:as]
      @constraints = (@options[:constraints] || {}).freeze
      @defaults = (@options[:defaults] || {}).transform_keys(&:to_s).freeze
      @param_key_slots = [[nil, nil], [nil, nil]]
      @required_validated_once = false

      setup_caches

      precompile_route_data
      validate_route!
    end

    # Test if this route matches an HTTP method + path string.
    #
    # @param request_method [String, Symbol] The HTTP method.
    # @param request_path [String] The request path.
    # @return [Boolean] `true` if the route matches, `false` otherwise.
    def match?(request_method, request_path)
      normalized_method = normalize_http_method(request_method)
      return false unless @methods_set.include?(normalized_method)

      !!extract_path_params_fast(request_path)
    end

    # @return [Boolean] Whether this route has a name.
    def named?
      !@name.nil?
    end

    # @return [Boolean] Heuristic: path contains `:id` implying a resource member.
    def resource?
      @is_resource
    end

    # @return [Boolean] Inverse of `#resource?`.
    def collection?
      !@is_resource
    end

    private

    # Expose for testing / external callers.
    public :extract_path_params_fast

    # Precompile route data for performance.
    #
    # @return [void]
    def precompile_route_data
      raw_http_methods = Array(@options[:via] || :get)
      @methods = raw_http_methods.map { |method| normalize_http_method(method) }.freeze
      @methods_set = @methods.to_set.freeze

      to_str = @options[:to].to_s
      to_controller, to_action = to_str.split('#', 2)
      @controller = @options[:controller] || to_controller
      @action = @options[:action] || to_action

      @is_resource = @path.match?(%r{/:id(?:$|\.)})

      setup_caches
      compile_segments
      compile_required_params
      check_static_path
    end
  end
end
