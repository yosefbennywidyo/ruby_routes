# frozen_string_literal: true

require 'uri'
require 'timeout'
require 'set'
require 'rack'
require_relative 'constant'
require_relative 'route/small_lru'
require_relative 'utility/path_utility'
require_relative 'utility/key_builder_utility'
require_relative 'utility/method_utility'

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
    include RubyRoutes::Utility::PathUtility
    include RubyRoutes::Utility::KeyBuilderUtility
    include RubyRoutes::Utility::MethodUtility

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
      @path = normalize_path(path)
      method_inputs = Array(options[:via] || :get)
      @methods      = method_inputs.map { |http_method| normalize_method(http_method) }.freeze
      @methods_set  = @methods.to_set.freeze
      @controller   = extract_controller(options)
      @action       = options[:action] || extract_action(options[:to])
      @name         = options[:as]
      @constraints  = options[:constraints] || {}
      @defaults     = (options[:defaults] || {}).transform_keys(&:to_s).freeze

      # Micro‑caches
      @merged_cache_slots      = [[nil, nil], [nil, nil]]
      @param_key_slots         = [[nil, nil], [nil, nil]]

      # Step: cache required param validation (boolean sentinel)
      # After first successful validation we skip future required param checks
      # (NOTE: assumes callers do not later drop required params; aligns with action item spec).
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

    # Parse query params (wrapper for internal caching).
    #
    # @param path [String]
    # @return [Hash]
    def parse_query_params(path)
      query_params_fast(path)
    end
    alias_method :query_params, :parse_query_params

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
      if (params.nil? || params.empty?)
        return @static_path if @static_path
        # If no user params & no required params, we can skip validation entirely
        return @static_path || RubyRoutes::Constant::ROOT_PATH if @required_params.empty? && @compiled_segments.empty?
      end

      # Cache required param validation (action item)
      unless @required_params.empty? || @required_validated_once
        missing, nils = validate_required_params(params)
        raise RouteNotFound, "Missing params: #{missing.join(', ')}" unless missing.empty?
        raise RouteNotFound, "Missing or nil params: #{nils.join(', ')}" unless nils.empty?
        @required_validated_once = true if missing.empty? && nils.empty?
      end

      merged = build_merged_params(params)

      cache_key =
        if @required_params.empty?
          KeyBuilderUtility::EMPTY_PARAMS_KEY
        else
          build_param_cache_key(merged)
        end

      if (cached = @gen_cache.get(cache_key))
        return cached
      end

      path_str = generate_path_string(merged)
      @gen_cache.set(cache_key, path_str)
      path_str
    end

    # Internal: merged params (defaults + user) with small identity cache.
    #
    # @param params [Hash]
    # @return [Hash]
    def build_merged_params(params)
      return @defaults if params.nil? || params.empty?
      hash = Thread.current[:ruby_routes_merge_hash] ||= {}
      hash.clear
      @defaults.each { |key, value| hash[key] = value }
      params.each do |key, value|
        next if value.nil?
        key_string = key.is_a?(String) ? key : key.to_s
        hash[key_string] = value
      end
      hash
    end
    private :build_merged_params

    # Build / reuse param key for path generation cache.
    #
    # @param merged [Hash]
    # @return [String]
    def build_param_cache_key(merged)
      raw_key = param_cache_key_reuse(@required_params, merged)
      hash_val = raw_key.hash
      if @param_key_slots[0][0] == hash_val
        return @param_key_slots[0][1]
      elsif @param_key_slots[1][0] == hash_val
        return @param_key_slots[1][1]
      end
      frozen_key = raw_key.freeze
      if @param_key_slots[0][0].nil?
        @param_key_slots[0] = [hash_val, frozen_key]
      elsif @param_key_slots[1][0].nil?
        @param_key_slots[1] = [hash_val, frozen_key]
      else
        @param_key_slots[0] = @param_key_slots[1]
        @param_key_slots[1] = [hash_val, frozen_key]
      end
      frozen_key
    end
    private :build_param_cache_key

    # (Legacy shim – left for backward compatibility references.)
    def build_merged_params_fast(params)
      build_merged_params(params)
    end
    alias_method :build_merged_params_legacy, :build_merged_params_fast

    # Acquire pooled Hash for merging.
    #
    # @return [Hash]
    def get_thread_local_merged_hash
      pool = Thread.current[:ruby_routes_merge_hash_pool] ||= []
      return {} if pool.empty?
      hash = pool.pop
      hash.clear
      hash
    end

    # Return merged hash to pool (not always used).
    #
    # @param hash [Hash]
    # @return [void]
    def return_merged_hash_to_pool(hash)
      pool = Thread.current[:ruby_routes_merge_hash_pool] ||= []
      pool << hash if pool.size < 4
    end
    private :get_thread_local_merged_hash, :return_merged_hash_to_pool

    # Precompile internal data (segments, caches, static path).
    #
    # @return [void]
    def precompile_route_data
      @is_resource = @path.match?(/\/:id(?:$|\.)/)
      @gen_cache   = SmallLru.new(512)
      @query_cache = SmallLru.new(RubyRoutes::Constant::QUERY_CACHE_SIZE)
      initialize_validation_cache
      compile_segments
      compile_required_params
      check_static_path
    end

    # Convert raw path into frozen descriptors.
    #
    # @return [void]
    def compile_segments
      @compiled_segments =
        if @path == RubyRoutes::Constant::ROOT_PATH
          RubyRoutes::Constant::EMPTY_ARRAY
        else
          @path.split('/').reject(&:empty?).map { |seg| RubyRoutes::Constant.segment_descriptor(seg) }.freeze
        end
    end

    # Derive required param names excluding those with defaults.
    #
    # @return [void]
    def compile_required_params
      dynamic_names = @compiled_segments.filter_map { |segment| segment[:name] if segment[:type] != :static }
      @param_names        = dynamic_names.freeze
      @required_params    = dynamic_names.reject { |name| @defaults.key?(name) }.freeze
      @required_params_set = @required_params.to_set.freeze
    end

    # Precompute static path if no dynamic parts.
    def check_static_path
      return unless @compiled_segments.all? { |seg| seg[:type] == :static }
      @static_path = generate_static_path
    end

    # Build static path.
    #
    # @return [String]
    def generate_static_path
      return RubyRoutes::Constant::ROOT_PATH if @compiled_segments.empty?
      parts = @compiled_segments.map { |segment| segment[:value] }
      "/#{parts.join('/')}"
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

    # Thread‑local pooled hash for param extraction.
    #
    # @return [Hash]
    def get_thread_local_hash
      pool = Thread.current[:ruby_routes_hash_pool] ||= []
      return {} if pool.empty?
      hash = pool.pop
      hash.clear
      hash
    end

    # Return hash to pool.
    #
    # @param hash [Hash]
    def return_hash_to_pool(hash)
      pool = Thread.current[:ruby_routes_hash_pool] ||= []
      pool.push(hash) if pool.size < 5
    end

    # Merge defaults where absent.
    #
    # @param result [Hash]
    def merge_defaults_fast(result)
      @defaults.each { |key, value| result[key] = value unless result.key?(key) }
    end

    # Fast extraction of dynamic params from a path.
    #
    # @param request_path [String]
    # @return [Hash, nil] nil when mismatch
    def extract_path_params_fast(request_path)
      return RubyRoutes::Constant::EMPTY_HASH if @compiled_segments.empty? && request_path == RubyRoutes::Constant::ROOT_PATH
      return nil if @compiled_segments.empty?

      path_parts = split_path(request_path)
      contains_splat = @compiled_segments.any? { |seg| seg[:type] == :splat }

      if contains_splat
        return nil if path_parts.size < @compiled_segments.size - 1
      else
        return nil if @compiled_segments.size != path_parts.size
      end
      extract_params_from_parts(path_parts)
    end

    # Iterate compiled segments and map values.
    #
    # @param path_parts [Array<String>]
    # @return [Hash, nil]
    def extract_params_from_parts(path_parts)
      extracted = {}
      @compiled_segments.each_with_index do |segment, index|
        case segment[:type]
        when :static
          return nil unless segment[:value] == path_parts[index]
        when :param
          extracted[segment[:name]] = path_parts[index]
        when :splat
          extracted[segment[:name]] = path_parts[index..-1].join('/')
          break
        end
      end
      extracted
    end

    # Construct a generated path string from merged params.
    #
    # @param merged [Hash]
    # @return [String]
    def generate_path_string(merged)
      return RubyRoutes::Constant::ROOT_PATH if @compiled_segments.empty?

      estimation = 1
      @compiled_segments.each do |segment|
        case segment[:type]
        when :static
          estimation += segment[:value].length + 1
        when :param, :splat
          estimation += 20
        end
      end

      path_buffer = String.new(capacity: estimation)
      path_buffer << '/'
      last_index = @compiled_segments.size - 1

      @compiled_segments.each_with_index do |segment, index|
        case segment[:type]
        when :static
          path_buffer << segment[:value]
        when :param
          raw_value = merged.fetch(segment[:name]).to_s
          path_buffer << encode_segment_fast(raw_value)
        when :splat
          raw_value = merged.fetch(segment[:name], '')
          path_buffer << format_splat_value(raw_value)
        end
        path_buffer << '/' unless index == last_index
      end
      path_buffer
    end

    # Format a splat value (Array/String/other) into a path fragment.
    #
    # @param value [Object]
    # @return [String]
    def format_splat_value(value)
      case value
      when Array
        value.map { |part| encode_segment_fast(part.to_s) }.join('/')
      when String
        value.split('/').map { |part| encode_segment_fast(part) }.join('/')
      else
        encode_segment_fast(value.to_s)
      end
    end

    # Encode path segment if needed (reserved chars percent‑encoded).
    #
    # @param segment_string [String]
    # @return [String]
    def encode_segment_fast(segment_string)
      return segment_string if RubyRoutes::Constant::UNRESERVED_RE.match?(segment_string)
      @encoding_cache ||= {}
      @encoding_cache[segment_string] ||= URI.encode_www_form_component(segment_string).gsub('+', '%20')
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

    # Validate required parameters; returns pair of arrays:
    # [missing_keys, nil_value_keys]
    #
    # @param params [Hash]
    # @return [Array<(Array,String)>]
    def validate_required_params(params)
      return RubyRoutes::Constant::EMPTY_PAIR if @required_params.empty?
      missing_keys   = nil
      nil_value_keys = nil
      @required_params.each do |required_key|
        if params.key?(required_key)
          (nil_value_keys ||= []) << required_key if params[required_key].nil?
        elsif params.key?(sym = required_key.to_sym)
          (nil_value_keys ||= []) << required_key if params[sym].nil?
        else
          (missing_keys ||= []) << required_key
        end
      end
      [missing_keys || RubyRoutes::Constant::EMPTY_ARRAY, nil_value_keys || RubyRoutes::Constant::EMPTY_ARRAY]
    end

    # Initialize validation result cache.
    #
    # @return [void]
    def initialize_validation_cache
      @validation_cache = SmallLru.new(64)
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

    # Detect param structure type (used for potential future optimizations).
    #
    # @param params [Object]
    # @return [Symbol] :string_keyed_hash, :symbol_keyed_hash, :hash, :enumerable, :other
    def params_type(params)
      @params_type_cache ||= {}
      object_id = params.object_id
      return @params_type_cache[object_id] if @params_type_cache.key?(object_id)

      type = if params.is_a?(Hash)
        refine_hash_type(params)
      elsif params.respond_to?(:each) && params.respond_to?(:[])
        :enumerable
      else
        :other
      end

      @params_type_cache.clear if @params_type_cache.size > 100
      @params_type_cache[object_id] = type
    end

    # Sample keys to classify hash kind.
    #
    # @param params [Hash]
    # @return [Symbol]
    def refine_hash_type(params)
      samples = params.keys.take(3)
      if samples.all? { |k| k.is_a?(String) }
        :string_keyed_hash
      elsif samples.all? { |k| k.is_a?(Symbol) }
        :symbol_keyed_hash
      else
        :hash
      end
    end

    # Validate constraint rules quickly.
    #
    # @param params [Hash]
    # @raise [RubyRoutes::ConstraintViolation]
    def validate_constraints_fast!(params)
      @constraints.each do |constraint_key, constraint|
        value = params[constraint_key.to_s]
        next unless params.key?(constraint_key.to_s)

        case constraint
        when Regexp
          begin
            Timeout.timeout(0.1) { raise RubyRoutes::ConstraintViolation unless constraint.match?(value.to_s) }
          rescue Timeout::Error
            raise RubyRoutes::ConstraintViolation, 'Regex constraint timed out (potential ReDoS attack)'
          end
        when Proc
          warn_proc_constraint_deprecation(constraint_key)
          begin
            Timeout.timeout(0.05) { raise RubyRoutes::ConstraintViolation unless constraint.call(value.to_s) }
          rescue Timeout::Error
            raise RubyRoutes::ConstraintViolation, 'Proc constraint timed out'
          rescue => e
            raise RubyRoutes::ConstraintViolation, "Proc constraint failed: #{e.message}"
          end
        when :int
          raise RubyRoutes::ConstraintViolation unless value.to_s.match?(/\A\d+\z/)
        when :uuid
          v = value.to_s
          raise RubyRoutes::ConstraintViolation unless v.length == 36 &&
            v.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
        when :email
          raise RubyRoutes::ConstraintViolation unless value.to_s.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
        when :slug
          raise RubyRoutes::ConstraintViolation unless value.to_s.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)
        when :alpha
          raise RubyRoutes::ConstraintViolation unless value.to_s.match?(/\A[a-zA-Z]+\z/)
        when :alphanumeric
          raise RubyRoutes::ConstraintViolation unless value.to_s.match?(/\A[a-zA-Z0-9]+\z/)
        when Hash
          validate_hash_constraint!(constraint, value.to_s)
        end
      end
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

    # Validate fundamental route shape.
    #
    # @raise [InvalidRoute]
    def validate_route!
      raise InvalidRoute, 'Controller is required' if @controller.nil?
      raise InvalidRoute, 'Action is required' if @action.nil?
      raise InvalidRoute, "Invalid HTTP method: #{@methods}" if @methods.empty?
    end

    # HTTP method normalization wrapper (uses MethodUtility).
    #
    # @param method [String, Symbol]
    # @return [String]
    def normalize_method(method)
      normalize_http_method(method)
    end
  end
 end
