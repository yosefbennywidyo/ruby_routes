# frozen_string_literal: true

require 'uri'
require 'timeout'
require 'rack'
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
  # - Instance is effectively read‑only after initialization aside from
  #   internal caches which are not synchronized but safe for typical
  #   single writer (boot) + many reader (request) usage.
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
    include RubyRoutes::Utility::MethodUtility
    include RubyRoutes::Utility::PathUtility
    include RubyRoutes::Utility::KeyBuilderUtility

    attr_reader :path, :methods, :controller, :action, :name, :constraints, :defaults

    # Create a new Route.
    #
    # @param path [String] raw route path (may include :params or *splat)
    # @param options [Hash]
    # @option options [Symbol, String, Array<Symbol,String>] :via (:get) HTTP method(s)
    # @option options [String] :to ("controller#action")
    # @option options [String] :controller explicit controller (overrides :to)
    # @option options [String, Symbol] :action explicit action (overrides part after '#')
    # @option options [Hash] :constraints param constraints (Regex / Symbol / Hash)
    # @option options [Hash] :defaults default param values
    # @option options [Symbol, String] :as route name
    def initialize(path, options = {})
      @path              = normalize_path(path)
      raw_methods        = Array(options[:via] || :get)
      @methods           = raw_methods.map { |m| normalize_http_method(m) }.freeze
      @methods_set       = @methods.to_set.freeze
      @controller        = extract_controller(options)
      @action            = options[:action] || extract_action(options[:to])
      @name              = options[:as]
      @constraints       = options[:constraints] || {}
      @defaults          = (options[:defaults] || {}).transform_keys(&:to_s).freeze
      @param_key_slots   = [[nil, nil], [nil, nil]]
      @required_validated_once = false

      precompile_route_data
      validate_route!
    end

    # Test if this route matches an HTTP method + path string.
    #
    # @param request_method [String, Symbol]
    # @param request_path [String]
    # @return [Boolean]
    def match?(request_method, request_path)
      normalized = normalize_http_method(request_method)
      return false unless @methods_set.include?(normalized)

      !!extract_path_params_fast(request_path)
    end

    # Extract parameters from a request path (and optionally pre‑parsed query).
    #
    # @param request_path [String]
    # @param parsed_qp [Hash, nil] pre-parsed query params to merge (optional)
    # @return [Hash] frozen defaults merged in; NOT frozen (mutable for caller)
    def extract_params(request_path, parsed_qp = nil)
      path_params = extract_path_params_fast(request_path)
      return RubyRoutes::Constant::EMPTY_HASH unless path_params

      build_params_hash(path_params, request_path, parsed_qp)
    end

    # @return [Boolean] whether this route has a name.
    def named?
      !@name.nil?
    end

    # @return [Boolean] heuristic: path contains :id implying a resource member.
    def resource?
      @is_resource
    end

    # @return [Boolean] inverse of #resource?
    def collection?
      !@is_resource
    end

    # Query param parsing w/ simple LRU.
    #
    # @param path [String]
    # @return [Hash]
    def query_params_fast(path)
      index = path.index('?')
      return RubyRoutes::Constant::EMPTY_HASH unless index
      query_string = path[(index + 1)..-1]
      return RubyRoutes::Constant::EMPTY_HASH if query_string.empty? || query_string.match?(/^\?+$/)
      if (cached = @query_cache.get(query_string))
        return cached
      end
      result = Rack::Utils.parse_query(query_string)
      @query_cache.set(query_string, result)
      result
    end

    # Parse query params (wrapper for internal caching).
    #
    # @param path [String]
    # @return [Hash]
    def parse_query_params(path)
      query_params_fast(path)
    end
    alias query_params parse_query_params

    # Generate a path string from supplied params.
    #
    # Rules:
    # - Required params must be present & non‑nil (unless defaulted).
    # - Caches result keyed on ordered required param values.
    #
    # @param params [Hash] parameters (String/Symbol keys)
    # @return [String]
    # @raise [RouteNotFound] when required params missing / nil
    def generate_path(params = {})
      if params.nil? || params.empty?
        return @static_path if @static_path
        # If no user params & no required params, we can skip validation entirely
        return @static_path || RubyRoutes::Constant::ROOT_PATH if @required_params.empty? && @compiled_segments.empty?
      end

      validate_required_once(params)

      merged = build_merged_params(params)

      cache_key =
        if @required_params.empty?
          RubyRoutes::Constant::EMPTY_STRING
        else
          build_param_cache_key(merged)
        end

      if (hit = @gen_cache.get(cache_key))
        return hit
      end

      built = generate_path_string(merged)
      @gen_cache.set(cache_key, built)
      built
    end

    private

    # Infer controller name from options or :to.
    #
    # @param options [Hash]
    # @return [String, nil]
    def extract_controller(options)
      to = options[:to]
      return options[:controller] unless to
      to.to_s.split('#', 2).first
    end

    # Infer action from :to string.
    #
    # @param to [String, nil]
    # @return [String, nil]
    def extract_action(to)
      return nil unless to
      to.to_s.split('#', 2).last
    end

    # Initialize validation result cache.
    #
    # @return [void]
    def initialize_validation_cache
      @validation_cache = SmallLru.new(64)
    end

    # Validate fundamental route shape.
    #
    # @raise [InvalidRoute]
    def validate_route!
      raise InvalidRoute, 'Controller is required' if @controller.nil?
      raise InvalidRoute, 'Action is required' if @action.nil?
      raise InvalidRoute, "Invalid HTTP method: #{@methods}" if @methods.empty?
    end

    def precompile_route_data
      @is_resource = @path.match?(%r{/:id(?:$|\.)})
      @gen_cache   = SmallLru.new(512)
      @query_cache = SmallLru.new(RubyRoutes::Constant::QUERY_CACHE_SIZE)
      initialize_validation_cache
      compile_segments
      compile_required_params
      check_static_path
    end

    def validate_required_once(params)
      return if @required_params.empty? || @required_validated_once

      missing, nils = validate_required_params(params)
      raise RouteNotFound, "Missing params: #{missing.join(', ')}" unless missing.empty?
      raise RouteNotFound, "Missing or nil params: #{nils.join(', ')}" unless nils.empty?

      @required_validated_once = true
    end

    # Slightly simplified
    def validate_required_params(params)
      return RubyRoutes::Constant::EMPTY_PAIR if @required_params.empty?

      missing = nil
      nils    = nil
      @required_params.each do |rk|
        if params.key?(rk)
          (nils ||= []) << rk if params[rk].nil?
        elsif params.key?(sym = rk.to_sym)
          (nils ||= []) << rk if params[sym].nil?
        else
          (missing ||= []) << rk
        end
      end
      [missing || RubyRoutes::Constant::EMPTY_ARRAY,
       nils    || RubyRoutes::Constant::EMPTY_ARRAY]
    end

    # Cache validation result (immutable params only).
    #
    # @param params [Hash]
    # @param result [Object]
    def cache_validation_result(params, result)
      if params.frozen? && @validation_cache && @validation_cache.size < 64
        @validation_cache.set(params.hash, result)
      end
    end

    # Fetch cached validation result.
    #
    # @param params [Hash]
    # @return [Object, nil]
    def get_cached_validation(params)
      return nil unless @validation_cache
      @validation_cache.get(params.hash)
    end

    # Build full params hash (path + query + defaults + constraints).
    #
    # @param path_params [Hash]
    # @param request_path [String]
    # @param parsed_qp [Hash, nil]
    # @return [Hash]
    def build_params_hash(path_params, request_path, parsed_qp)
      params_hash = get_thread_local_hash
      params_hash.update(path_params)

      if parsed_qp
        params_hash.merge!(parsed_qp)
      elsif request_path.include?('?')
        query_hash = query_params_fast(request_path)
        params_hash.merge!(query_hash) unless query_hash.empty?
      end

      merge_defaults_fast(params_hash) unless @defaults.empty?
      validate_constraints_fast!(params_hash) unless @constraints.empty?
      params_hash
    end

    # Emit deprecation warning for Proc constraints once per parameter.
    #
    # @param param [String, Symbol]
    # @return [void]
    def warn_proc_constraint_deprecation(param)
      return if @proc_warnings_shown&.include?(param)
      @proc_warnings_shown ||= Set.new
      @proc_warnings_shown << param
      warn <<~WARNING
        [DEPRECATION] Proc constraints are deprecated due to security risks.

        Parameter: #{param}
        Route: #{@path}

        Secure alternatives:
        - Use regex: constraints: { #{param}: /\\A\\d+\\z/ }
        - Use built-in types: constraints: { #{param}: :int }
        - Use hash constraints: constraints: { #{param}: { min_length: 3, format: /\\A[a-z]+\\z/ } }

        Available built-in types: :int, :uuid, :email, :slug, :alpha, :alphanumeric

        This warning will become an error in a future version.
      WARNING
    end

    # Return hash to pool.
    #
    # @param hash [Hash]
    def return_hash_to_pool(hash)
      pool = Thread.current[:ruby_routes_hash_pool] ||= []
      pool.push(hash) if pool.size < 5
    end

    # Validate hash-form constraint rules.
    #
    # @param constraint [Hash]
    # @param value [String]
    # @raise [RubyRoutes::ConstraintViolation]
    def validate_hash_constraint!(constraint, value)
      if constraint[:min_length] && value.length < constraint[:min_length]
        raise RubyRoutes::ConstraintViolation, "Value too short (minimum #{constraint[:min_length]} characters)"
      end
      if constraint[:max_length] && value.length > constraint[:max_length]
        raise RubyRoutes::ConstraintViolation, "Value too long (maximum #{constraint[:max_length]} characters)"
      end
      if constraint[:format] && !value.match?(constraint[:format])
        raise RubyRoutes::ConstraintViolation, 'Value does not match required format'
      end
      if constraint[:in] && !constraint[:in].include?(value)
        raise RubyRoutes::ConstraintViolation, 'Value not in allowed list'
      end
      if constraint[:not_in] && constraint[:not_in].include?(value)
        raise RubyRoutes::ConstraintViolation, 'Value in forbidden list'
      end
      if constraint[:range] && !constraint[:range].cover?(value.to_i)
        raise RubyRoutes::ConstraintViolation, 'Value not in allowed range'
      end
    end

    # Merge defaults where absent.
    #
    # @param result [Hash]
    def merge_defaults_fast(result)
      @defaults.each { |key, value| result[key] = value unless result.key?(key) }
    end

    # Renamed accessor (was get_thread_local_hash)
    def acquire_thread_local_hash
      pool = Thread.current[:ruby_routes_hash_pool] ||= []
      return {} if pool.empty?

      h = pool.pop
      h.clear
      h
    end

    alias get_thread_local_hash acquire_thread_local_hash # backward compatibility if referenced elsewhere
  end
end
