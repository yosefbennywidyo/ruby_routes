require 'cgi'

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
      safe_text = CGI.escapeHTML(text.to_s)
      "<a href=\"#{path}\">#{safe_text}</a>"
    end

    def button_to(name, text, params = {})
      local_params = params ? params.dup : {}
      method = local_params.delete(:method) || :post
      method = method.to_s.downcase
      path = path_to(name, local_params)

      # HTML forms only support GET and POST
      # For other methods, use POST with _method hidden field
      form_method = (method == 'get') ? 'get' : 'post'
      
      html = "<form action=\"#{path}\" method=\"#{form_method}\">"
      
      # Add _method hidden field for non-GET/POST methods
      if method != 'get' && method != 'post'
        html += "<input type=\"hidden\" name=\"_method\" value=\"#{method}\">"
      end
      
      safe_text = CGI.escapeHTML(text.to_s)
      html += "<button type=\"submit\">#{safe_text}</button>"
      html += "</form>"
      html
    end

    def redirect_to(name, params = {})
      path = path_to(name, params)
      { status: 302, location: path }
    end
  end
end
