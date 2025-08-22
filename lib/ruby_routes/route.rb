require 'uri'
require 'timeout'
require 'set'
require 'rack'
require_relative 'route/small_lru'

module RubyRoutes
  class Route
    attr_reader :path, :methods, :controller, :action, :name, :constraints, :defaults

    def initialize(path, options = {})
      @path = normalize_path(path)
      # Pre-normalize and freeze methods at creation time
      raw_methods = Array(options[:via] || :get)
      @methods = raw_methods.map { |m| normalize_method(m) }.freeze
      @methods_set = @methods.to_set.freeze
      @controller = extract_controller(options)
      @action = options[:action] || extract_action(options[:to])
      @name = options[:as]
      @constraints = options[:constraints] || {}
      # Pre-normalize defaults to string keys and freeze
      @defaults = (options[:defaults] || {}).transform_keys(&:to_s).freeze

      # Pre-compile everything at initialization
      precompile_route_data
      validate_route!
    end

    def match?(request_method, request_path)
      # Fast method check: use frozen Set for O(1) lookup
      return false unless @methods_set.include?(request_method.to_s.upcase)
      !!extract_path_params_fast(request_path)
    end

    def extract_params(request_path, parsed_qp = nil)
      path_params = extract_path_params_fast(request_path)

      return EMPTY_HASH unless path_params

      # Use optimized param building
      build_params_hash(path_params, request_path, parsed_qp)
    end

    def named?
      !@name.nil?
    end

    def resource?
      @is_resource
    end

    def collection?
      !@is_resource
    end

    def parse_query_params(path)
      query_params_fast(path)
    end

    # Optimized path generation with better caching and fewer allocations
    def generate_path(params = {})
      return ROOT_PATH if @path == ROOT_PATH

      # Fast path: empty params and no required params
      if params.empty? && @required_params.empty?
        return @static_path if @static_path
      end

      # Build merged params efficiently
      merged = build_merged_params(params)

      # Check required params (fast Set operation)
      missing_params = @required_params_set - merged.keys
      unless missing_params.empty?
        raise RubyRoutes::RouteNotFound, "Missing params: #{missing_params.to_a.join(', ')}"
      end

      # Check for nil values in required params
      nil_params = @required_params_set.select { |param| merged[param].nil? }
      unless nil_params.empty?
        raise RubyRoutes::RouteNotFound, "Missing or nil params: #{nil_params.to_a.join(', ')}"
      end

      # Cache lookup
      cache_key = build_cache_key_fast(merged)
      if (cached = @gen_cache.get(cache_key))
        return cached
      end

      # Generate path using string buffer (avoid array allocations)
      path_str = generate_path_string(merged)
      @gen_cache.set(cache_key, path_str)
      path_str
    end

    # Fast query params method (cached and optimized)
    def query_params(request_path)
      query_params_fast(request_path)
    end

    private

    # Constants for performance
    EMPTY_HASH = {}.freeze
    ROOT_PATH = '/'.freeze
    UNRESERVED_RE = /\A[a-zA-Z0-9\-._~]+\z/.freeze
    QUERY_CACHE_SIZE = 128

    # Common HTTP methods - interned for performance
    HTTP_GET = 'GET'.freeze
    HTTP_POST = 'POST'.freeze
    HTTP_PUT = 'PUT'.freeze
    HTTP_PATCH = 'PATCH'.freeze
    HTTP_DELETE = 'DELETE'.freeze
    HTTP_HEAD = 'HEAD'.freeze
    HTTP_OPTIONS = 'OPTIONS'.freeze

    # Fast method normalization using interned constants
    def normalize_method(method)
      case method
      when :get then HTTP_GET
      when :post then HTTP_POST
      when :put then HTTP_PUT
      when :patch then HTTP_PATCH
      when :delete then HTTP_DELETE
      when :head then HTTP_HEAD
      when :options then HTTP_OPTIONS
      else method.to_s.upcase.freeze
      end
    end

    # Pre-compile all route data at initialization
    def precompile_route_data
      @is_resource = @path.match?(/\/:id(?:$|\.)/)
      @gen_cache = SmallLru.new(512)  # larger cache
      @query_cache = SmallLru.new(QUERY_CACHE_SIZE)

      compile_segments
      compile_required_params
      check_static_path
    end

    def compile_segments
      @compiled_segments = if @path == ROOT_PATH
                             EMPTY_ARRAY
                           else
                             @path.split('/').reject(&:empty?).map do |seg|
                               RubyRoutes::Constant.segment_descriptor(seg)
                             end.freeze
                           end
    end

    def compile_required_params
      param_names = @compiled_segments.filter_map { |s| s[:name] if s[:type] != :static }
      @param_names = param_names.freeze
      @required_params = param_names.reject { |n| @defaults.key?(n) }.freeze
      @required_params_set = @required_params.to_set.freeze
    end

    def check_static_path
      # Pre-generate static paths (no params)
      if @required_params.empty?
        @static_path = generate_static_path
      end
    end

    def generate_static_path
      return ROOT_PATH if @compiled_segments.empty?

      parts = @compiled_segments.map { |seg| seg[:value] }
      "/#{parts.join('/')}"
    end

    # Optimized param building
    def build_params_hash(path_params, request_path, parsed_qp)
      # Use pre-allocated hash when possible
      result = get_thread_local_hash

      # Path params first (highest priority)
      result.update(path_params)

      # Query params (if needed)
      if parsed_qp
        result.merge!(parsed_qp)
      elsif request_path.include?('?')
        qp = query_params_fast(request_path)
        result.merge!(qp) unless qp.empty?
      end

      # Defaults (lowest priority)
      merge_defaults_fast(result) unless @defaults.empty?

      # Validate constraints efficiently
      validate_constraints_fast!(result) unless @constraints.empty?

      result.dup
    end

    def get_thread_local_hash
      # Use a pool of hashes to reduce allocations
      pool = Thread.current[:ruby_routes_hash_pool] ||= []
      if pool.empty?
        {}
      else
        hash = pool.pop
        hash.clear
        hash
      end
    end

    def return_hash_to_pool(hash)
      pool = Thread.current[:ruby_routes_hash_pool] ||= []
      pool.push(hash) if pool.size < 5  # Keep pool small to avoid memory bloat
    end

    def merge_defaults_fast(result)
      @defaults.each { |k, v| result[k] = v unless result.key?(k) }
    end

    # Fast path parameter extraction
    def extract_path_params_fast(request_path)
      return EMPTY_HASH if @compiled_segments.empty? && request_path == ROOT_PATH
      return nil if @compiled_segments.empty?

      path_parts = split_path_fast(request_path)

      # Check for wildcard/splat segment
      has_splat = @compiled_segments.any? { |seg| seg[:type] == :splat }

      if has_splat
        return nil if path_parts.size < @compiled_segments.size - 1
      else
        return nil if @compiled_segments.size != path_parts.size
      end

      extract_params_from_parts(path_parts)
    end

    def split_path_fast(request_path)
      # Remove query string before splitting
      path = request_path.split('?', 2).first
      path = path[1..-1] if path.start_with?('/')
      path = path[0...-1] if path.end_with?('/') && path != ROOT_PATH
      path.empty? ? [] : path.split('/')
    end

    def extract_params_from_parts(path_parts)
      params = {}

      @compiled_segments.each_with_index do |seg, idx|
        case seg[:type]
        when :static
          return nil unless seg[:value] == path_parts[idx]
        when :param
          params[seg[:name]] = path_parts[idx]
        when :splat
          params[seg[:name]] = path_parts[idx..-1].join('/')
          break
        end
      end

      params
    end

    # Optimized merged params building
    def build_merged_params(params)
      return @defaults if params.empty?

      merged = get_thread_local_merged_hash

      # Merge defaults first if they exist
      merged.update(@defaults) unless @defaults.empty?

      # Use merge! with transform_keys for better performance
      if params.respond_to?(:transform_keys)
        merged.merge!(params.transform_keys(&:to_s))
      else
        # Fallback for older Ruby versions
        params.each { |k, v| merged[k.to_s] = v }
      end

      merged
    end

    def get_thread_local_merged_hash
      hash = Thread.current[:ruby_routes_merged] ||= {}
      hash.clear
      hash
    end

    # Fast cache key building with minimal allocations
    def build_cache_key_fast(merged)
      return '' if @required_params.empty?

      # Use array join which is faster than string concatenation
      parts = @required_params.map do |name|
        value = merged[name]
        value.is_a?(Array) ? value.join('/') : value.to_s
      end
      parts.join('|')
    end

    # Optimized path generation
    def generate_path_string(merged)
      return ROOT_PATH if @compiled_segments.empty?

      # Pre-allocate array for parts to avoid string buffer operations
      parts = []

      @compiled_segments.each do |seg|
        case seg[:type]
        when :static
          parts << seg[:value]
        when :param
          value = merged.fetch(seg[:name]).to_s
          parts << encode_segment_fast(value)
        when :splat
          value = merged.fetch(seg[:name], '')
          parts << format_splat_value(value)
        end
      end

      # Single join operation is faster than multiple string concatenations
      path = "/#{parts.join('/')}"
      path == '/' ? ROOT_PATH : path
    end

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

    # Fast segment encoding with caching for common values
    def encode_segment_fast(str)
      return str if UNRESERVED_RE.match?(str)

      # Cache encoded segments to avoid repeated encoding
      @encoding_cache ||= {}
      @encoding_cache[str] ||= begin
        # Use URI.encode_www_form_component but replace + with %20 for path segments
        URI.encode_www_form_component(str).gsub('+', '%20')
      end
    end

    # Optimized query params with caching
    def query_params_fast(path)
      query_start = path.index('?')
      return EMPTY_HASH unless query_start

      query_string = path[(query_start + 1)..-1]
      return EMPTY_HASH if query_string.empty? || query_string.match?(/^\?+$/)

      # Cache query param parsing
      if (cached = @query_cache.get(query_string))
        return cached
      end

      result = Rack::Utils.parse_query(query_string)
      @query_cache.set(query_string, result)
      result
    end

    def normalize_path(path)
      path_str = path.to_s
      path_str = "/#{path_str}" unless path_str.start_with?('/')
      path_str = path_str.chomp('/') unless path_str == ROOT_PATH
      path_str
    end

    def extract_controller(options)
      to = options[:to]
      return options[:controller] unless to
      to.to_s.split('#', 2).first
    end

    def extract_action(to)
      return nil unless to
      to.to_s.split('#', 2).last
    end

    # Optimized constraint validation
    def validate_constraints_fast!(params)
      @constraints.each do |param, constraint|
        value = params[param.to_s]
        # Only skip validation if the parameter is completely missing from params
        # Empty strings and nil values should still be validated
        next unless params.key?(param.to_s)

        case constraint
        when Regexp
          # Protect against ReDoS attacks with timeout
          begin
            Timeout.timeout(0.1) do
              raise RubyRoutes::ConstraintViolation unless constraint.match?(value.to_s)
            end
          rescue Timeout::Error
            raise RubyRoutes::ConstraintViolation, "Regex constraint timed out (potential ReDoS attack)"
          end
        when Proc
          # DEPRECATED: Proc constraints are deprecated due to security risks
          warn_proc_constraint_deprecation(param)

          # For backward compatibility, still execute but with strict timeout
          begin
            Timeout.timeout(0.05) do  # Reduced timeout for security
              raise RubyRoutes::ConstraintViolation unless constraint.call(value.to_s)
            end
          rescue Timeout::Error
            raise RubyRoutes::ConstraintViolation, "Proc constraint timed out (consider using secure alternatives)"
          rescue => e
            raise RubyRoutes::ConstraintViolation, "Proc constraint failed: #{e.message}"
          end
        when :int
          value_str = value.to_s
          raise RubyRoutes::ConstraintViolation unless value_str.match?(/\A\d+\z/)
        when :uuid
          value_str = value.to_s
          raise RubyRoutes::ConstraintViolation unless value_str.length == 36 &&
                 value_str.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
        when :email
          value_str = value.to_s
          raise RubyRoutes::ConstraintViolation unless value_str.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
        when :slug
          value_str = value.to_s
          raise RubyRoutes::ConstraintViolation unless value_str.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)
        when :alpha
          value_str = value.to_s
          raise RubyRoutes::ConstraintViolation unless value_str.match?(/\A[a-zA-Z]+\z/)
        when :alphanumeric
          value_str = value.to_s
          raise RubyRoutes::ConstraintViolation unless value_str.match?(/\A[a-zA-Z0-9]+\z/)
        when Hash
          # Secure hash-based constraints for common patterns
          validate_hash_constraint!(constraint, value_str = value.to_s)
        end
      end
    end

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

    def validate_hash_constraint!(constraint, value)
      # Secure hash-based constraints
      if constraint[:min_length] && value.length < constraint[:min_length]
        raise RubyRoutes::ConstraintViolation, "Value too short (minimum #{constraint[:min_length]} characters)"
      end

      if constraint[:max_length] && value.length > constraint[:max_length]
        raise RubyRoutes::ConstraintViolation, "Value too long (maximum #{constraint[:max_length]} characters)"
      end

      if constraint[:format] && !value.match?(constraint[:format])
        raise RubyRoutes::ConstraintViolation, "Value does not match required format"
      end

      if constraint[:in] && !constraint[:in].include?(value)
        raise RubyRoutes::ConstraintViolation, "Value not in allowed list"
      end

      if constraint[:not_in] && constraint[:not_in].include?(value)
        raise RubyRoutes::ConstraintViolation, "Value in forbidden list"
      end

      if constraint[:range] && !constraint[:range].cover?(value.to_i)
        raise RubyRoutes::ConstraintViolation, "Value not in allowed range"
      end
    end

    def validate_route!
      raise InvalidRoute, "Controller is required" if @controller.nil?
      raise InvalidRoute, "Action is required" if @action.nil?
      raise InvalidRoute, "Invalid HTTP method: #{@methods}" if @methods.empty?
    end

    # Additional constants
    EMPTY_ARRAY = [].freeze
    EMPTY_STRING = ''.freeze
  end
 end
