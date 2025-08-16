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
      !!extract_path_params(request_path)
    end

    def extract_params(request_path)
      path_params = extract_path_params(request_path)
      return {} unless path_params

      params = path_params.dup
      params.merge!(query_params(request_path))
      params.merge!(defaults.transform_keys(&:to_s))

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

    private

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
      route_parts = path.split('/')
      request_parts = request_path.split('/')

      return nil if route_parts.size != request_parts.size

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

    def query_params(path)
      return {} unless path.include?('?')
      Rack::Utils.parse_query(path.split('?').last).transform_keys(&:to_s)
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
