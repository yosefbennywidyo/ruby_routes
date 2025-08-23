# frozen_string_literal: true

require 'cgi'

module RubyRoutes
  # UrlHelpers
  #
  # Mixin that provides named route helper methods (e.g., `user_path`),
  # HTML link/button helpers, and simple redirect data structures.
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
  # - `#path_to(name, params)` → String path
  # - `#url_to(name, params)` → Absolute URL (host hard‑coded: localhost)
  # - `#link_to(name, text, params)` → HTML anchor tag
  # - `#button_to(name, text, params)` → HTML form button
  # - `#redirect_to(name, params)` → { status:, location: }
  #
  # Requirements:
  # - Including class must define `#route_set` returning a `RouteSet`.
  #
  # @api public
  module UrlHelpers
    # Hook for when the module is included.
    #
    # @param base [Class] The class including the module.
    # @return [void]
    def self.included(base)
      base.extend(ClassMethods)
      base.include(base.url_helpers)
    end

    # Class‑level DSL for defining dynamic helper methods.
    module ClassMethods
      # Module storing dynamically defined helper methods (memoized).
      #
      # @return [Module] The module containing dynamically defined helpers.
      def url_helpers
        @url_helpers ||= Module.new
      end

      # Define a named route helper method.
      #
      # @param name [Symbol] The helper method name (e.g., `:user_path`).
      # @param route [RubyRoutes::Route] The route instance.
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
    # @return [Module] The module containing dynamically defined helpers.
    def url_helpers
      self.class.url_helpers
    end

    # Resolve a named route to a path.
    #
    # @param name [Symbol, String] The route name.
    # @param params [Hash] The parameter substitutions.
    # @return [String] The generated path.
    def path_to(name, params = {})
      route = route_set.find_named_route(name)
      route_set.generate_path_from_route(route, params)
    end

    # Resolve a named route to a full (hard‑coded host) URL.
    #
    # @param name [Symbol, String] The route name.
    # @param params [Hash] The parameter substitutions.
    # @return [String] The absolute URL.
    def url_to(name, params = {})
      path = path_to(name, params)
      "http://localhost#{path}"
    end

    # Build an HTML anchor tag for a named route.
    #
    # @param name [Symbol, String] The route name.
    # @param text [String] The link text.
    # @param params [Hash] The parameter substitutions.
    # @return [String] The HTML-safe anchor tag.
    def link_to(name, text, params = {})
      path = path_to(name, params)
      escaped_path = CGI.escapeHTML(path.to_s)
      escaped_text = CGI.escapeHTML(text.to_s)
      "<a href=\"#{escaped_path}\">#{escaped_text}</a>"
    end

    # Build a minimal HTML form acting as a button submission to a named route.
    #
    # Supports non-GET/POST methods via a hidden `_method` field (Rails style).
    #
    # @param name [Symbol, String] The route name.
    # @param text [String] The button label.
    # @param params [Hash] The parameter substitutions, including optional `:method`.
    # @option params [Symbol, String] :method (:post) The HTTP method.
    # @return [String] The HTML form markup.
    def button_to(name, text, params = {})
      params_copy = params ? params.dup : {}
      method = params_copy.delete(:method) || :post
      method = method.to_s.downcase
      path = path_to(name, params_copy)
      form_method = method == 'get' ? 'get' : 'post'
      build_form_html(path, form_method, method, text)
    end

    # Build a simple redirect structure (framework adapter can translate).
    #
    # @param name [Symbol, String] The route name.
    # @param params [Hash] The parameter substitutions.
    # @return [Hash] A hash containing the redirect status and location.
    def redirect_to(name, params = {})
      path = path_to(name, params)
      { status: 302, location: path }
    end

    private

    # Build the form HTML.
    #
    # @param path [String] The form action path.
    # @param form_method [String] The form method (e.g., "get" or "post").
    # @param method [String] The HTTP method (e.g., "put" or "delete").
    # @param text [String] The button label.
    # @return [String] The HTML form markup.
    def build_form_html(path, form_method, method, text)
      escaped_path = CGI.escapeHTML(path.to_s)
      escaped_form_method = CGI.escapeHTML(form_method)
      form_html = "<form action=\"#{escaped_path}\" method=\"#{escaped_form_method}\">"

      if method != 'get' && method != 'post'
        escaped_method = CGI.escapeHTML(method)
        form_html += "<input type=\"hidden\" name=\"_method\" value=\"#{escaped_method}\">"
      end

      escaped_text = CGI.escapeHTML(text.to_s)
      form_html + "<button type=\"submit\">#{escaped_text}</button></form>"
    end
  end
end
