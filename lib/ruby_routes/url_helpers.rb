module RubyRoutes
  module UrlHelpers
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def url_helpers
        @url_helpers ||= Module.new
      end

      def add_url_helper(name, route)
        url_helpers.define_method(name) do |*args|
          params = args.first || {}
          route_set.generate_path_from_route(route, params)
        end
      end
    end

    def url_helpers
      self.class.url_helpers
    end

    def path_to(name, params = {})
      route = route_set.find_named_route(name)
      route_set.generate_path_from_route(route, params)
    end

    def url_to(name, params = {})
      path = path_to(name, params)
      "http://localhost#{path}"
    end

    def link_to(name, text, params = {})
      path = path_to(name, params)
      "<a href=\"#{path}\">#{text}</a>"
    end

    def button_to(name, text, params = {})
      path = path_to(name, params)
      method = params.delete(:method) || :post

      html = "<form action=\"#{path}\" method=\"#{method}\">"
      html += "<input type=\"hidden\" name=\"_method\" value=\"#{method}\">" if method != :get
      html += "<button type=\"submit\">#{text}</button>"
      html += "</form>"
      html
    end

    def redirect_to(name, params = {})
      path = path_to(name, params)
      { status: 302, location: path }
    end
  end
end
