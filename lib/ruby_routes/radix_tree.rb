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
          params[current.param_name] = segment
        elsif current.wildcard_child
          current = current.wildcard_child
          params[current.param_name] = segments[index..-1].join('/')
          break
        else
          return [nil, {}]
        end
      end

      handler = current.get_handler(method)
      current.is_endpoint ? [handler, params] : [nil, {}]
    end

    private

    def split_path(path)
      return [''] if path == '/'
      path.gsub(/^\//, '').gsub(/\/$/, '').split('/')
    end
  end
end
