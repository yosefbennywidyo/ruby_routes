# frozen_string_literal: true

require 'uri'
require 'timeout'
require 'rack'
require 'set'
require_relative 'constant'
require_relative 'node'
require_relative 'route/small_lru'
require_relative 'utility/key_builder_utility'
require_relative 'utility/method_utility'
require_relative 'utility/path_utility'
require_relative 'utility/route_utility'
require_relative 'route/param_support'
require_relative 'route/segment_compiler'
require_relative 'route/path_builder'
require_relative 'route/constraint_validator'
require_relative 'route/check_helpers'
require_relative 'route/query_helpers'
require_relative 'route/validation_helpers'
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
    include SegmentCompiler
    include PathBuilder
    include RubyRoutes::Route::ConstraintValidator
    include RubyRoutes::Route::ValidationHelpers
    include RubyRoutes::Route::QueryHelpers
    include RubyRoutes::Route::PathGeneration
    include RubyRoutes::Utility::MethodUtility
    include RubyRoutes::Utility::PathUtility
    include RubyRoutes::Utility::KeyBuilderUtility

    attr_reader :path, :methods, :controller, :action, :name, :constraints, :defaults

    public :extract_params, :parse_query_params, :query_params, :generate_path

    # Create a new Route.
    #
    # @param path [String] The raw route path (may include `:params` or `*splat`).
    # @param options [Hash] The options for the route.
    # @option options [Symbol, String, Array<Symbol, String>] :via (:get) HTTP method(s).
    # @option options [String] :to ("controller#action") The controller and action.
    # @option options [String] :controller Explicit controller (overrides `:to`).
    # @option options [String, Symbol] :action Explicit action (overrides part after `#`).
    # @option options [Hash] :constraints Parameter constraints (Regexp / Symbol / Hash).
    # @option options [Hash] :defaults Default parameter values.
    # @option options [Symbol, String] :as The route name.
    def initialize(path, options = {})
      @path = normalize_path(path)

      setup_methods(options)
      setup_controller_and_action(options)

      @name = options[:as]
      @constraints = (options[:constraints] || {}).freeze
      @defaults = (options[:defaults] || {}).transform_keys(&:to_s).freeze
      @param_key_slots = [[nil, nil], [nil, nil]]
      @required_validated_once = false

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

    # Set up HTTP methods from options.
    #
    # @param options [Hash] The options for the route.
    # @return [void]
    def setup_methods(options)
      raw_http_methods = Array(options[:via] || :get)
      @methods = raw_http_methods.map { |method| normalize_http_method(method) }.freeze
      @methods_set = @methods.to_set.freeze
    end

    # Set up controller and action from options.
    #
    # @param options [Hash] The options for the route.
    # @return [void]
    def setup_controller_and_action(options)
      @controller = extract_controller(options)
      @action = options[:action] || extract_action(options[:to])
    end

    # Infer controller name from options or `:to`.
    #
    # @param options [Hash] The options for the route.
    # @return [String, nil] The inferred controller name.
    def extract_controller(options)
      return options[:controller] if options[:controller]
      to = options[:to]
      return nil unless to

      to.to_s.split('#', 2).first
    end

    # Infer action from `:to` string.
    #
    # @param to [String, nil] The `:to` string.
    # @return [String, nil] The inferred action name.
    def extract_action(to)
      return nil unless to

      to.to_s.split('#', 2).last
    end

    # Precompile route data for performance.
    #
    # @return [void]
    def precompile_route_data
      @is_resource = @path.match?(%r{/:id(?:$|\.)})
      @gen_cache = SmallLru.new(512)
      @query_cache = SmallLru.new(RubyRoutes::Constant::QUERY_CACHE_SIZE)
      @cache_mutex = Mutex.new  # Thread-safe access to caches
      initialize_validation_cache
      compile_segments
      compile_required_params
      check_static_path
    end
  end
end
