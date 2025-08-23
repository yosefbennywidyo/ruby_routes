require 'cgi'

module RubyRoutes
  # UrlHelpers
  #
  # Mixin that provides named route helper methods (e.g. user_path),
  # HTML link / button helpers, and simple redirect data structures.
  #
  # Inclusion pattern:
  #   class Application
  #     include RubyRoutes::UrlHelpers
  #     def route_set; ROUTES end
  #   end
  #
  # When a Route is named, router code should call:
  #   add_url_helper(:user_path, route_instance)
  #
  # This defines:
  #   user_path(params = {}) -> "/users/1"
  #
  # Public instance methods:
  # - #path_to(name, params)     → String path
  # - #url_to(name, params)      → Absolute URL (host hard‑coded: localhost)
  # - #link_to(name, text, params)
  # - #button_to(name, text, params)
  # - #redirect_to(name, params) → { status:, location: }
  #
  # Requirements:
  # - Including class must define #route_set returning a RouteSet.
  #
  # @api public
  module UrlHelpers
    def self.included(base)
      base.extend(ClassMethods)
      base.include(base.url_helpers)
    end

    # Class‑level DSL for defining dynamic helper methods.
    module ClassMethods
      # Module storing dynamically defined helper methods (memoized).
      #
      # @return [Module]
      def url_helpers
        @url_helpers ||= Module.new
      end

      # Define a named route helper method.
      #
      # @param name [Symbol] helper method name (e.g., :user_path)
      # @param route [RubyRoutes::Route]
      # @return [void]
      def add_url_helper(name, route)
        url_helpers.define_method(name) do |*args|
          params = args.first || {}
            route_set.generate_path_from_route(route, params)
        end
      end
    end

    # Access the dynamically generated helpers module (instance side).
    #
    # @return [Module]
    def url_helpers
      self.class.url_helpers
    end

    # Resolve a named route to a path.
    #
    # @param name [Symbol, String] route name
    # @param params [Hash] parameter substitutions
    # @return [String]
    def path_to(name, params = {})
      route = route_set.find_named_route(name)
      route_set.generate_path_from_route(route, params)
    end

    # Resolve a named route to a full (hard‑coded host) URL.
    #
    # @param name [Symbol, String]
    # @param params [Hash]
    # @return [String] absolute URL
    def url_to(name, params = {})
      path = path_to(name, params)
      "http://localhost#{path}"
    end

    # Build an HTML anchor tag for a named route.
    #
    # @param name [Symbol, String]
    # @param text [String] link text
    # @param params [Hash]
    # @return [String] HTML-safe string
    def link_to(name, text, params = {})
      path = path_to(name, params)
      safe_path = CGI.escapeHTML(path.to_s)
      safe_text = CGI.escapeHTML(text.to_s)
      "<a href=\"#{safe_path}\">#{safe_text}</a>"
    end

    # Build a minimal HTML form acting as a button submission to a named route.
    #
    # Supports non-GET/POST methods via hidden _method field (Rails style).
    #
    # @param name [Symbol, String]
    # @param text [String] button label
    # @param params [Hash] includes optional :method
    # @option params [Symbol,String] :method (:post) HTTP method
    # @return [String] HTML form markup
    def button_to(name, text, params = {})
      local_params = params ? params.dup : {}
      method = local_params.delete(:method) || :post
      method = method.to_s.downcase
      path = path_to(name, local_params)

      # HTML forms only support GET and POST; emulate others with hidden field.
      form_method = (method == 'get') ? 'get' : 'post'

      safe_path = CGI.escapeHTML(path.to_s)
      safe_form_method = CGI.escapeHTML(form_method)
      html = "<form action=\"#{safe_path}\" method=\"#{safe_form_method}\">"

      if method != 'get' && method != 'post'
        safe_method = CGI.escapeHTML(method)
        html += "<input type=\"hidden\" name=\"_method\" value=\"#{safe_method}\">"
      end

      safe_text = CGI.escapeHTML(text.to_s)
      html += "<button type=\"submit\">#{safe_text}</button>"
      html += "</form>"
      html
    end

    # Build a simple redirect structure (framework adapter can translate).
    #
    # @param name [Symbol, String]
    # @param params [Hash]
    # @return [Hash] { status: 302, location: "/path" }
    def redirect_to(name, params = {})
      path = path_to(name, params)
      { status: 302, location: path }
    end
  end
end
