require 'uri'

module RubyRoutes
  class Route
    # small LRU used for path generation cache
    class SmallLru
      attr_reader :hits, :misses, :evictions

      # larger default to reduce eviction likelihood in benchmarks
      def initialize(max_size = 1024)
        @max_size = max_size
        @h = {}
        @hits = 0
        @misses = 0
        @evictions = 0
        @disabled = false
      end

      def get(key)
        return nil if @disabled
        if @h.key?(key)
          @hits += 1
          val = @h.delete(key)
          @h[key] = val
          val
        else
          @misses += 1
          nil
        end
      end

      def set(key, val)
        return val if @disabled
        @h.delete(key) if @h.key?(key)
        @h[key] = val
        if @h.size > @max_size
          @h.shift
          @evictions += 1
        end
        # Simple thrash detection: when evictions grow beyond 2x capacity, disable cache.
        if @evictions > (@max_size * 2)
          @disabled = true
          @h.clear
        end
        val
      end
    end

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

    def extract_params(request_path)
      path_params = extract_path_params(request_path)
      return {} unless path_params

      params = path_params.dup
      params.merge!(query_params(request_path)) # query_params returns string-keyed hash below
      # defaults already string keys, only merge keys that aren't present
      defaults.each { |k, v| params[k] = v unless params.key?(k) }

      validate_constraints!(params)
      params
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

    # Public, allocation-cheap query parser wrapper
    # Delegates to the private query_params implementation which returns
    # a string-keyed hash (Rack::Utils.parse_query already returns strings).
    def parse_query_params(path)
      query_params(path)
    end

    # Fast path generator: uses precompiled token list and a small LRU.
    # Avoids unbounded cache growth and skips URI-encoding for safe values.
    def generate_path(params = {})
      return '/' if path == '/'

      # build merged for only relevant param names
      merged = {}
      defaults.each { |k, v| merged[k] = v } # defaults already string keys
      params.each do |k, v|
        ks = k.to_s
        merged[ks] = v
      end

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
            if seg.start_with?(':')
              { type: :param, name: seg[1..-1] }
            elsif seg.start_with?('*')
              { type: :splat, name: (seg[1..-1] || 'splat') }
            else
              { type: :static, value: seg }
            end
          end
        end
      end
    end

    def compiled_required_params
      @compiled_required_params ||= compiled_segments.select { |s| s[:type] != :static }
                                                  .map { |s| s[:name] }.uniq
                                                  .reject { |n| defaults.key?(n) }
    end

    # Cache key: deterministic param-order key (fast, stable)
    def cache_key_for(merged)
      # build key in route token order (parameters & splat) to avoid sorting/inspect
      # handle arrays (splats) explicitly and avoid `inspect`
      names = compiled_param_names
      names.map do |n|
        v = merged[n]
        if v.nil?
          ''
        elsif v.is_a?(Array)
          v.map(&:to_s).join('/')
        else
          v.to_s
        end
      end.join('|')
    end

    def compiled_param_names
      @compiled_param_names ||= compiled_segments.map { |s| s[:name] if s[:type] != :static }.compact
    end

    # Only URI-encode a segment when it contains unsafe chars.
    UNRESERVED_RE = /\A[a-zA-Z0-9\-._~]+\z/
    def safe_encode_segment(str)
      # leave slash handling to splat logic (splats already split)
      # cheap, fast check first: ascii-only unreserved chars avoid allocation
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
      Rack::Utils.parse_query(qs).transform_keys(&:to_s)
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
