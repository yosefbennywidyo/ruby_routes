module RubyRoutes
  class RadixTree
    attr_reader :root

    def initialize
      @root = Node.new
    end

    def add_route(path, method, handler, constraints: {})
      segments = path.split('/').reject(&:empty?)
      current = @root

      segments.each do |segment|
        if segment.start_with?('*')
          # Wildcard segment
          current.wildcard_child ||= Node.new
          current = current.wildcard_child
          current.param_name = segment[1..-1] || 'splat'
          break # Wildcard must be last segment
        elsif segment.start_with?(':')
          # Dynamic segment
          param_name = segment[1..-1]
          current.dynamic_child ||= Node.new
          current = current.dynamic_child
          current.param_name = param_name
        else
          # Static segment
          current.static_children[segment] ||= Node.new
          current = current.static_children[segment]
        end
      end

      current.add_handler(method, handler, constraints: constraints)
    end

    def find_route(path, method)
      segments = path.split('/').reject(&:empty?)
      current = @root
      params = {}
      wildcard = nil

      segments.each_with_index do |segment, index|
        # 1. Check static match
        if current.static_children.key?(segment)
          current = current.static_children[segment]
        # 2. Check dynamic segment
        elsif current.dynamic_child
          current = current.dynamic_child
          params[current.param_name.to_sym] = segment
        # 3. Check for wildcard
        elsif current.wildcard_child
          current = current.wildcard_child
          wildcard = segments[index..-1].join('/')
          params[current.param_name.to_sym] = wildcard
          break
        else
          return [nil, {}] # No match
        end
      end

      handler_info = current.get_handler(method)
      return [handler_info, params] if handler_info && current.is_endpoint

      [nil, {}]
    end
  end
end
