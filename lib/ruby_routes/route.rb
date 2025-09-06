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
require_relative 'segment'
require_relative 'route/path_builder'
require_relative 'route/constraint_validator'
require_relative 'route/check_helpers'
require_relative 'route/query_helpers'
require_relative 'route/validation_helpers'
require_relative 'route/path_generation'
require_relative 'route_set/cache_helpers'

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
    include RubyRoutes::Utility::MethodUtility
    include RubyRoutes::Utility::PathUtility
    include RubyRoutes::Utility::KeyBuilderUtility
    include RubyRoutes::RouteSet::CacheHelpers

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

    # Compile the segments from the path using Segment objects.
    #
    # @return [void]
    def compile_segments
      @compiled_segments =
        if @path == RubyRoutes::Constant::ROOT_PATH
          RubyRoutes::Constant::EMPTY_ARRAY
        else
          @path.split('/').reject(&:empty?)
               .map { |segment| RubyRoutes::Segment.for(segment) }
               .freeze
        end
    end

    # Compile the required parameters.
    #
    # This method identifies dynamic parameters in the path and determines
    # which parameters are required based on the defaults provided.
    #
    # @return [void]
    def compile_required_params
      dynamic_param_names   = @compiled_segments.filter_map { |segment| segment.param_name if segment.respond_to?(:param_name) && segment.param_name }
      @param_names          = dynamic_param_names.freeze
      @required_params      = if @defaults.empty?
                                dynamic_param_names.freeze
                              else
                                dynamic_param_names.reject do |name|
                                  @defaults.key?(name) || (@defaults.key?(name.to_sym) if name.is_a?(String))
                                end.freeze
                              end
      @required_params_set  = @required_params.to_set.freeze
    end

    # Check if the path is static.
    #
    # This method determines if the path contains only static segments. If so,
    # it generates the static path.
    #
    # @return [void]
    def check_static_path
      return unless @compiled_segments.all? { |segment| segment.is_a?(RubyRoutes::Segments::StaticSegment) }

      @static_path = generate_static_path
    end

    # Generate the static path.
    #
    # This method constructs the static path from the compiled segments.
    #
    # @return [String] The generated static path.
    def generate_static_path
      return RubyRoutes::Constant::ROOT_PATH if @compiled_segments.empty?

      "/#{@compiled_segments.map { |segment| segment.instance_variable_get(:@literal_text) }.join('/')}"
    end

    # Extract path parameters fast using Segment objects.
    #
    # This method extracts parameters from a request path based on the compiled
    # segments.
    #
    # @param request_path [String] The request path.
    # @return [Hash, nil] The extracted parameters, or `nil` if extraction fails.
    def extract_path_params_fast(request_path)
      return RubyRoutes::Constant::EMPTY_HASH if root_path_and_empty_segments?(request_path)

      return nil if @compiled_segments.empty?

      path_parts = split_path(request_path)
      return nil unless valid_parts_count?(path_parts)

      extract_params_from_parts(path_parts)
    end

    # Check if it's a root path with empty segments.
    #
    # @param request_path [String] The request path.
    # @return [Boolean]
    def root_path_and_empty_segments?(request_path)
      @compiled_segments.empty? && request_path == RubyRoutes::Constant::ROOT_PATH
    end

    # Validate the parts count.
    #
    # @param path_parts [Array<String>] The path parts.
    # @return [Boolean]
    def valid_parts_count?(path_parts)
      has_wildcard = @compiled_segments.any? { |segment| segment.wildcard? }
      (!has_wildcard && path_parts.size == @compiled_segments.size) ||
        (has_wildcard && path_parts.size >= (@compiled_segments.size - 1))
    end

    # Extract parameters from parts.
    #
    # @param path_parts [Array<String>] The path parts.
    # @return [Hash, nil]
    def extract_params_from_parts(path_parts)
      params_hash = {}
      @compiled_segments.each_with_index do |segment, index|
        result = process_segment(segment, index, path_parts, params_hash)
        return nil if result == false
        break if result == :break
      end
      params_hash
    end

    # Process a segment.
    #
    # @param segment [RubyRoutes::Segments::BaseSegment] The segment object.
    # @param index [Integer] The index of the segment.
    # @param path_parts [Array<String>] The path parts.
    # @param params_hash [Hash] The parameters hash.
    # @return [Boolean, Symbol]
    def process_segment(segment, index, path_parts, params_hash)
      case segment
      when RubyRoutes::Segments::StaticSegment
        segment.instance_variable_get(:@literal_text) == path_parts[index]
      when RubyRoutes::Segments::DynamicSegment
        params_hash[segment.param_name] = path_parts[index]
        true
      when RubyRoutes::Segments::WildcardSegment
        params_hash[segment.param_name] = path_parts[index..].join('/')
        :break
      end
    end

    # Split path into parts.
    #
    # @param path [String] The path to split.
    # @return [Array<String>]
    def split_path(path)
      path.split('/').reject(&:empty?)
    end

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

      initialize_validation_cache
      compile_segments
      compile_required_params
      check_static_path
    end

  end
end
