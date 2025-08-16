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
      @defaults = options[:defaults] || {}

      validate_route!
    end

    def match?(request_method, request_path)
      return false unless methods.include?(request_method.to_s.upcase)

      path_params = extract_path_params(request_path)
      path_params != nil
    end

    def extract_params(request_path)
      path_params = extract_path_params(request_path)
      return {} unless path_params

      params = path_params.dup
      # Convert symbol keys to string keys for consistency
      string_defaults = defaults.transform_keys(&:to_s)
      params.merge!(string_defaults)
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

    private

    def normalize_path(path)
      path = "/#{path}" unless path.start_with?('/')
      # Remove trailing slash unless it's the root path
      path = path.chomp('/') unless path == '/'
      path
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
      route_parts = path.split('/')
      request_parts = request_path.split('/')

      return nil if route_parts.length != request_parts.length

      params = {}
      route_parts.each_with_index do |route_part, index|
        request_part = request_parts[index]

        if route_part.start_with?(':')
          param_name = route_part[1..-1]
          params[param_name] = request_part
        elsif route_part != request_part
          return nil
        end
      end

      params
    end

    def validate_route!
      raise InvalidRoute, "Controller is required" if controller.nil?
      raise InvalidRoute, "Action is required" if action.nil?
      raise InvalidRoute, "Invalid HTTP method: #{methods}" if methods.empty?
    end
  end
end
