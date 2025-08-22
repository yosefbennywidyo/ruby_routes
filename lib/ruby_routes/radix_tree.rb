require_relative 'segment'

module RubyRoutes
  class RadixTree
    class << self
      # Allow RadixTree.new(path, options...) to act as a convenience factory
      def new(*args, &block)
        if args.any?
          RubyRoutes::Route.new(*args, &block)
        else
          super()
        end
      end
    end

    def initialize
      @root = Node.new
      @split_cache = {}
      @split_cache_order = []
      @split_cache_max = 2048      # larger cache for better hit rates
      @empty_segments = [].freeze  # reuse for root path
    end

    def add(path, methods, handler)
      current = @root
      segments = split_path_raw(path)

      segments.each do |raw_seg|
        seg = RubyRoutes::Segment.for(raw_seg)
        current = seg.ensure_child(current)
        break if seg.wildcard?
      end

      # Normalize methods once during registration
      Array(methods).each { |method| current.add_handler(method.to_s.upcase, handler) }
    end

    def find(path, method, params_out = nil)
      # Handle nil path and method cases
      path ||= ''
      method = method.to_s.upcase if method
      # Strip query string before matching
      clean_path = path.split('?', 2).first || ''
      # Fast path: root route
      if clean_path == '/' || clean_path.empty?
        handler = @root.get_handler(method)
        if @root.is_endpoint && handler
          return [handler, params_out || {}]
        else
          return [nil, {}]
        end
      end

      segments = split_path_cached(clean_path)
      current = @root
      params = params_out || {}
      params.clear if params_out

      # Unrolled traversal for common case (1-3 segments)
      case segments.size
      when 1
        next_node, _ = current.traverse_for(segments[0], 0, segments, params)
        current = next_node
      when 2
        next_node, should_break = current.traverse_for(segments[0], 0, segments, params)
        return [nil, {}] unless next_node
        current = next_node
        unless should_break
          next_node, _ = current.traverse_for(segments[1], 1, segments, params)
          current = next_node
        end
      when 3
        next_node, should_break = current.traverse_for(segments[0], 0, segments, params)
        return [nil, {}] unless next_node
        current = next_node
        unless should_break
          next_node, should_break = current.traverse_for(segments[1], 1, segments, params)
          return [nil, {}] unless next_node
          current = next_node
          unless should_break
            next_node, _ = current.traverse_for(segments[2], 2, segments, params)
            current = next_node
          end
        end
      else
        # General case for longer paths
        segments.each_with_index do |text, idx|
          next_node, should_break = current.traverse_for(text, idx, segments, params)
          return [nil, {}] unless next_node
          current = next_node
          break if should_break
        end
      end

      return [nil, {}] unless current
      handler = current.get_handler(method)
      return [nil, {}] unless current.is_endpoint && handler

      # Fast constraint check
      if handler.respond_to?(:constraints) && !handler.constraints.empty?
        return [nil, {}] unless constraints_match_fast(handler.constraints, params)
      end

      [handler, params]
    end

    private

    # Cached path splitting with optimized common cases
    def split_path_cached(path)
      return @empty_segments if path == '/' || path.empty?

      if (cached = @split_cache[path])
        return cached
      end

      result = split_path_raw(path)

      # Cache with simple LRU eviction
      @split_cache[path] = result
      @split_cache_order << path
      if @split_cache_order.size > @split_cache_max
        oldest = @split_cache_order.shift
        @split_cache.delete(oldest)
      end

      result
    end

    # Raw path splitting without caching (for registration)
    def split_path_raw(path)
      return [] if path == '/' || path.empty?

      # Optimized trimming: avoid string allocations when possible
      start_idx = path.start_with?('/') ? 1 : 0
      end_idx = path.end_with?('/') ? -2 : -1

      if start_idx == 0 && end_idx == -1
        path.split('/')
      else
        path[start_idx..end_idx].split('/')
      end
    end

    # Optimized constraint matching with fast paths
    def constraints_match_fast(constraints, params)
      constraints.each do |param, constraint|
        # Try both string and symbol keys (common pattern)
        value = params[param.to_s]
        value ||= params[param] if param.respond_to?(:to_s)
        next unless value

        case constraint
        when Regexp
          return false unless constraint.match?(value)
        when Proc
          return false unless constraint.call(value)
        when :int
          # Fast integer check without regex
          return false unless value.is_a?(String) && value.match?(/\A\d+\z/)
        when :uuid
          # Fast UUID check
          return false unless value.is_a?(String) && value.length == 36 &&
                             value.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
        when Symbol
          # Handle other symbolic constraints
          next  # unknown symbol constraint — allow
        end
      end
      true
    end
  end
end
