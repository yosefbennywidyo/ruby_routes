# frozen_string_literal: true

require_relative 'build_helpers'
require_relative '../utility/inflector_utility'

module RubyRoutes
  class Router
    # ResourceHelpers: resource / nested-resource related helpers extracted
    # from HttpHelpers to reduce method length and ABC complexity.
    #
    # This module provides methods for defining RESTful routes for resources,
    # handling nested resources, and generating metadata for resource paths
    # and controller actions.
    module ResourceHelpers
      include RubyRoutes::Router::BuildHelpers

      # Define RESTful routes for a resource.
      #
      # @param resource_name [Symbol, String] The name of the resource.
      # @param options [Hash] Options for customizing the resource routes.
      #   - `:path` [String] Custom path for the resource.
      #   - `:controller` [String] Custom controller name.
      #   - `:nested` [Symbol, String] Name of the nested resource.
      # @param nested_block [Proc] A block for defining nested routes.
      # @return [void]
      def define_resource_routes(resource_name, options = {}, &nested_block)
        meta = resource_meta(resource_name, options)
        resource_opts = prepare_resource_options(options)

        push_scope(path: "/#{meta[:resource_path]}") do
          define_resource_actions(resource_opts, meta[:controller])
          handle_nested_option(options, resource_opts)
          apply_nested_block(nested_block)
        end
      end

      private

      # Prepare options for resource routes, removing the `:to` key to avoid conflicts.
      # This avoids creating a new hash if it's not necessary.
      #
      # @param options [Hash] The options hash.
      # @return [Hash] The prepared options.
      def prepare_resource_options(options)
        options.key?(:to) ? options.except(:to) : options
      end

      # Defines the seven standard RESTful actions for a resource.
      # This method is data-driven to reduce duplication and improve clarity.
      #
      # @param resource_opts [Hash] The options for the resource routes.
      # @param controller [String] The controller name for the actions.
      # @param member_param [String] The parameter name for member routes (e.g., ':id').
      # @return [void]
      def define_resource_actions(resource_opts, controller, member_param: ':id')
        # Collection routes
        add_route('',     build_route_options(resource_opts, :get,    "#{controller}#index"))
        add_route('/new', build_route_options(resource_opts, :get,    "#{controller}#new"))
        add_route('',     build_route_options(resource_opts, :post,   "#{controller}#create"))
        # Member routes
        add_route("/#{member_param}",      build_route_options(resource_opts, :get,    "#{controller}#show"))
        add_route("/#{member_param}/edit", build_route_options(resource_opts, :get,    "#{controller}#edit"))
        add_route("/#{member_param}",      resource_opts.merge(via: %i[put patch], to: "#{controller}#update"))
        add_route("/#{member_param}",      build_route_options(resource_opts, :delete, "#{controller}#destroy"))
      end

      # Apply a nested block of routes within the scope of a resource.
      #
      # @param nested_block [Proc] The block defining nested routes.
      # @return [void]
      def apply_nested_block(nested_block)
        return unless nested_block

        push_scope(path: '/:id') { instance_eval(&nested_block) }
      end

      # Prepare resource metadata (path/controller/action strings).
      #
      # @param resource_name [Symbol, String] The name of the resource.
      # @param options [Hash] Options for customizing the resource metadata.
      # @return [Hash] The resource metadata.
      def resource_meta(resource_name, options)
        base_name = resource_name.to_s
        resource_path = options[:path] ? options[:path].to_s : RubyRoutes::Utility::InflectorUtility.pluralize(base_name)
        controller = options[:controller] || RubyRoutes::Utility::InflectorUtility.pluralize(base_name)
        build_meta_hash(resource_path, controller)
      end

      # Build a metadata hash for a resource.
      #
      # @param resource_path [String] The resource path.
      # @param controller [String] The controller name.
      # @return [Hash] The metadata hash.
      def build_meta_hash(resource_path, controller)
        actions = %w[index new create show edit update destroy]
        meta_hash = actions.each_with_object({}) do |action, hash|
          hash[:"to_#{action}"] = "#{controller}##{action}"
        end

        meta_hash.merge(
          resource_path: resource_path,
          controller: controller
        )
      end

      # Handle the `nested:` shorthand option for resources.
      #
      # @param options [Hash] The options hash.
      # @param opts [Hash] The prepared options hash.
      # @return [void]
      def handle_nested_option(options, opts)
        return unless options[:nested]

        nested_name = options[:nested].to_s
        nested_path = RubyRoutes::Utility::InflectorUtility.pluralize(nested_name)
        push_scope(path: '/:id') do
          push_scope(path: "/#{nested_path}") do
            define_resource_actions(opts, nested_path, member_param: ':nested_id')
          end
        end
      end
    end
  end
end
