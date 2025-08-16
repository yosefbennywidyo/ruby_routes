module RubyRoutes
  class RadixTree
    class << self
      # Allow RadixTree.new(path, options...) to act as a convenience factory
      # returning a Route (this matches test usage where specs call
      # RadixTree.new('/path', to: 'controller#action')).
      # Calling RadixTree.new with no arguments returns an actual RadixTree instance.
      def new(*args, &block)
        if args.any?
          # Delegate to Route initializer when args are provided
          RubyRoutes::Route.new(*args, &block)
        else
          super()
        end
      end
    end

    def initialize
      @root = Node.new
      @_split_cache = {}           # simple LRU: key -> [value, age]
      @split_cache_order = []      # track order for eviction
      @split_cache_max = 1024
    end

    def add(path, methods, handler)
      segments = split_path(path)
      current = @root

      segments.each do |segment|
        if segment.start_with?('*')
          current.wildcard_child ||= Node.new
          current = current.wildcard_child
          current.param_name = segment[1..-1] || 'splat'
          break
        elsif segment.start_with?(':')
          current.dynamic_child ||= Node.new
          current = current.dynamic_child
          current.param_name = segment[1..-1]
        else
          current.static_children[segment] ||= Node.new
          current = current.static_children[segment]
        end
      end

      methods.each { |method| current.add_handler(method, handler) }
    end

    def find(path, method)
      segments = split_path(path)
      current = @root
      params = {}

      segments.each_with_index do |segment, index|
        if current.static_children.key?(segment)
          current = current.static_children[segment]
        elsif current.dynamic_child
          current = current.dynamic_child
          # keep string keys to avoid symbol allocations and extra conversions later
          params[current.param_name.to_s] = segment
        elsif current.wildcard_child
          current = current.wildcard_child
          params[current.param_name.to_s] = segments[index..-1].join('/')
          break
        else
          return [nil, {}]
        end
      end

      handler = current.get_handler(method)
      return [nil, {}] unless current.is_endpoint && handler

      # lightweight constraint checks: reject early if route constraints don't match
      route = handler
      if route.respond_to?(:constraints) && route.constraints.any?
        unless constraints_match?(route.constraints, params)
          return [nil, {}]
        end
      end

      [handler, params]
    end

    private

    # faster, lower-allocation trim + split
    def split_path(path)
      @split_cache ||= {}
      return [''] if path == '/'
      if (cached = @split_cache[path])
        return cached
      end

      p = path
      p = p[1..-1] if p.start_with?('/')
      p = p[0...-1] if p.end_with?('/')
      segs = p.split('/')

      # simple LRU insert
      @split_cache[path] = segs
      @split_cache_order << path
      if @split_cache_order.size > @split_cache_max
        oldest = @split_cache_order.shift
        @split_cache.delete(oldest)
      end

      segs
    end

    # constraints match helper (non-raising, lightweight)
    def constraints_match?(constraints, params)
      constraints.each do |param, constraint|
        value = params[param.to_s] || params[param]
        next unless value

        case constraint
        when Regexp
          return false unless constraint.match?(value)
        when Proc
          return false unless constraint.call(value)
        when Symbol
          case constraint
          when :int then return false unless value.match?(/^\d+$/)
          when :uuid then return false unless value.match?(/^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$/i)
          else
            # unknown symbol constraint — be conservative and allow
          end
        else
          # unknown constraint type — allow (Route will validate later if needed)
        end
      end
      true
    end
  end
end
