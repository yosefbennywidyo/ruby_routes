require 'uri'
require_relative 'route/small_lru'

module RubyRoutes
  class Route
    attr_reader :path, :methods, :controller, :action, :name, :constraints, :defaults

    def initialize(path, options = {})
      @path = normalize_path(path)
      @methods = Array(options[:via] || :get).map(&:to_s).map(&:upcase)
      @controller = extract_controller(options)
      @action = options[:action] || extract_action(options[:to])
      @name = options[:as]
      @constraints = options[:constraints] || {}
      # pre-normalize defaults to string keys to avoid per-request transform_keys
      @defaults = (options[:defaults] || {}).transform_keys(&:to_s)

      validate_route!
    end

    def match?(request_method, request_path)
      return false unless methods.include?(request_method.to_s.upcase)
      !!extract_path_params(request_path)
    end

    def extract_params(request_path, parsed_qp = nil)
      path_params = extract_path_params(request_path)
      return {} unless path_params

      # Reuse a thread-local hash to reduce allocations; return a dup to callers.
      tmp = Thread.current[:ruby_routes_params] ||= {}
      tmp.clear

      # start with path params (they take precedence)
      path_params.each { |k, v| tmp[k] = v }

      # use provided parsed_qp if available, otherwise parse lazily only if needed
      qp = parsed_qp
      if qp.nil? && request_path.include?('?')
        qp = query_params(request_path)
      end
      qp.each { |k, v| tmp[k] = v } if qp && !qp.empty?

      # only set defaults for keys not already present
      defaults.each { |k, v| tmp[k] = v unless tmp.key?(k) } if defaults

      validate_constraints!(tmp)
      tmp.dup
    end

    def named?
      !name.nil?
    end

    def resource?
      path.match?(/\/:id$/) || path.match?(/\/:id\./)
    end

    def collection?
      !resource?
    end

    def parse_query_params(path)
      query_params(path)
    end

    # Fast path generator: uses precompiled token list and a small LRU.
    # Avoids unbounded cache growth and skips URI-encoding for safe values.
    def generate_path(params = {})
      return '/' if path == '/'

      # build merged for only relevant param names, reusing a thread-local hash
      tmp = Thread.current[:ruby_routes_merged] ||= {}
      tmp.clear
      defaults.each { |k, v| tmp[k] = v } if defaults
      params.each { |k, v| tmp[k.to_s] = v } if params
      merged = tmp

      missing = compiled_required_params - merged.keys
      raise RubyRoutes::RouteNotFound, "Missing params: #{missing.join(', ')}" unless missing.empty?

      @gen_cache ||= SmallLru.new(256)
      cache_key = cache_key_for(merged)
      if (cached = @gen_cache.get(cache_key))
        return cached
      end

      parts = compiled_segments.map do |seg|
        case seg[:type]
        when :static
          seg[:value]
        when :param
          v = merged.fetch(seg[:name]).to_s
          safe_encode_segment(v)
        when :splat
          v = merged.fetch(seg[:name], '')
          arr = v.is_a?(Array) ? v : v.to_s.split('/')
          arr.map { |p| safe_encode_segment(p.to_s) }.join('/')
        end
      end

      out = '/' + parts.join('/')
      out = '/' if out == ''

      @gen_cache.set(cache_key, out)
      out
    end

    private

    # compile helpers (memoize)
    def compiled_segments
      @compiled_segments ||= begin
        if path == '/'
          []
        else
          path.split('/').reject(&:empty?).map do |seg|
            RubyRoutes::Constant.segment_descriptor(seg)
          end
        end
      end
    end

    def compiled_required_params
      @compiled_required_params ||= compiled_segments.select { |s| s[:type] != :static }
                                                  .map { |s| s[:name] }.uniq
                                                  .reject { |n| defaults.to_s.include?(n) }
    end

    # Cache key: deterministic param-order key (fast, stable)
    def cache_key_for(merged)
      # build key in route token order (parameters & splat) to avoid sorting/inspect
      names = compiled_param_names
      # build with single string buffer to avoid temporary arrays
      buf = +""
      names.each_with_index do |n, i|
        val = merged[n]
        part = if val.nil?
                 ''
               elsif val.is_a?(Array)
                 val.map!(&:to_s) && val.join('/')
               else
                 val.to_s
               end
        buf << '|' unless i.zero?
        buf << part
      end
      buf
    end

    def compiled_param_names
      @compiled_param_names ||= compiled_segments.map { |s| s[:name] if s[:type] != :static }.compact
    end

    # Only URI-encode a segment when it contains unsafe chars.
    UNRESERVED_RE = /\A[a-zA-Z0-9\-._~]+\z/
    def safe_encode_segment(str)
      # leave slash handling to splat logic (splats already split)
      return str if UNRESERVED_RE.match?(str)
      URI.encode_www_form_component(str)
    end

    def normalize_path(path)
      p = path.to_s
      p = "/#{p}" unless p.start_with?('/')
      p = p.chomp('/') unless p == '/'
      p
    end

    def extract_controller(options)
      if options[:to]
        options[:to].to_s.split('#').first
      else
        options[:controller]
      end
    end

    def extract_action(to)
      return nil unless to
      to.to_s.split('#').last
    end

    def extract_path_params(request_path)
      segs = compiled_segments # memoized compiled route tokens
      return nil if segs.empty? && request_path != '/'

      req = request_path
      req = req[1..-1] if req.start_with?('/')
      req = req[0...-1] if req.end_with?('/') && req != '/'
      request_parts = req == '' ? [] : req.split('/')

      return nil if segs.size != request_parts.size

      params = {}
      segs.each_with_index do |seg, idx|
        case seg[:type]
        when :static
          return nil unless seg[:value] == request_parts[idx]
        when :param
          params[seg[:name]] = request_parts[idx]
        when :splat
          params[seg[:name]] = request_parts[idx..-1].join('/')
          break
        end
      end

      params
    end

    def query_params(path)
      qidx = path.index('?')
      return {} unless qidx
      qs = path[(qidx + 1)..-1] || ''
      Rack::Utils.parse_query(qs)
    end

    def validate_constraints!(params)
      constraints.each do |param, constraint|
        value = params[param.to_s]
        next unless value

        case constraint
        when Regexp
          raise ConstraintViolation unless constraint.match?(value)
        when Proc
          raise ConstraintViolation unless constraint.call(value)
        when Symbol
          case constraint
          when :int then raise ConstraintViolation unless value.match?(/^\d+$/)
          when :uuid then raise ConstraintViolation unless value.match?(/^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$/i)
          end
        end
      end
    end

    def validate_route!
      raise InvalidRoute, "Controller is required" if controller.nil?
      raise InvalidRoute, "Action is required" if action.nil?
      raise InvalidRoute, "Invalid HTTP method: #{methods}" if methods.empty?
    end
  end
end
