require 'uri'
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

    # Fast method normalization
    def normalize_method(method)
      case method
      when :get then 'GET'
      when :post then 'POST'
      when :put then 'PUT'
      when :patch then 'PATCH'
      when :delete then 'DELETE'
      when :head then 'HEAD'
      when :options then 'OPTIONS'
      else method.to_s.upcase
      end.freeze
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
      hash = Thread.current[:ruby_routes_params] ||= {}
      hash.clear
      hash
    end

    def merge_defaults_fast(result)
      @defaults.each { |k, v| result[k] = v unless result.key?(k) }
    end

    # Fast path parameter extraction
    def extract_path_params_fast(request_path)
      return EMPTY_HASH if @compiled_segments.empty? && request_path == ROOT_PATH
      return nil if @compiled_segments.empty?

      # Fast path normalization
      path_parts = split_path_fast(request_path)
      return nil if @compiled_segments.size != path_parts.size

      extract_params_from_parts(path_parts)
    end

    def split_path_fast(request_path)
      # Optimized path splitting
      path = request_path
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
      merged.update(@defaults) unless @defaults.empty?

      # Convert param keys to strings efficiently
      params.each { |k, v| merged[k.to_s] = v }
      merged
    end

    def get_thread_local_merged_hash
      hash = Thread.current[:ruby_routes_merged] ||= {}
      hash.clear
      hash
    end

    # Fast cache key building with minimal allocations
    def build_cache_key_fast(merged)
      # Use instance variable buffer to avoid repeated allocations
      @cache_key_buffer ||= String.new(capacity: 128)
      @cache_key_buffer.clear

      return @cache_key_buffer.dup if @required_params.empty?

      @required_params.each_with_index do |name, idx|
        @cache_key_buffer << '|' unless idx.zero?
        value = merged[name]
        @cache_key_buffer << (value.is_a?(Array) ? value.join('/') : value.to_s) if value
      end
      @cache_key_buffer.dup
    end

    # Optimized path generation
    def generate_path_string(merged)
      return ROOT_PATH if @compiled_segments.empty?

      buffer = String.new(capacity: 128)
      buffer << '/'

      @compiled_segments.each_with_index do |seg, idx|
        buffer << '/' unless idx.zero?

        case seg[:type]
        when :static
          buffer << seg[:value]
        when :param
          value = merged.fetch(seg[:name]).to_s
          buffer << encode_segment_fast(value)
        when :splat
          value = merged.fetch(seg[:name], '')
          append_splat_value(buffer, value)
        end
      end

      buffer == '/' ? ROOT_PATH : buffer
    end

    def append_splat_value(buffer, value)
      case value
      when Array
        value.each_with_index do |part, idx|
          buffer << '/' unless idx.zero?
          buffer << encode_segment_fast(part.to_s)
        end
      when String
        parts = value.split('/')
        parts.each_with_index do |part, idx|
          buffer << '/' unless idx.zero?
          buffer << encode_segment_fast(part)
        end
      else
        buffer << encode_segment_fast(value.to_s)
      end
    end

    # Fast segment encoding
    def encode_segment_fast(str)
      return str if UNRESERVED_RE.match?(str)
      URI.encode_www_form_component(str)
    end

    # Optimized query params with caching
    def query_params_fast(path)
      query_start = path.index('?')
      return EMPTY_HASH unless query_start

      query_string = path[(query_start + 1)..-1]
      return EMPTY_HASH if query_string.empty?

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
        next unless value

        case constraint
        when Regexp
          raise ConstraintViolation unless constraint.match?(value)
        when Proc
          raise ConstraintViolation unless constraint.call(value)
        when :int
          raise ConstraintViolation unless value.match?(/\A\d+\z/)
        when :uuid
          raise ConstraintViolation unless value.length == 36 &&
                 value.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
        end
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
