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

      private

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
        opts = prepare_options(options)

        push_scope(path: "/#{meta[:resource_path]}") do
          build_routes(opts, meta)
          handle_nested_option(options, opts)
          apply_nested_block(nested_block)
        end
      end

      # Prepare options by removing the `:to` key if present.
      #
      # @param options [Hash] The options hash.
      # @return [Hash] The prepared options.
      def prepare_options(options)
        options.key?(:to) ? options.dup.tap { |h| h.delete(:to) } : options
      end

      # Build collection and member routes for a resource.
      #
      # @param opts [Hash] The options hash.
      # @param meta [Hash] The resource metadata.
      # @return [void]
      def build_routes(opts, meta)
        build_collection_routes(opts, meta[:to_index], meta[:to_new], meta[:to_create])
        build_member_routes(opts, meta[:to_show], meta[:to_edit], meta[:to_update], meta[:to_destroy])
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
        build_nested_routes(nested_path, opts)
      end

      # Build nested resource routes.
      #
      # @param nested_path [String] The path for the nested resource.
      # @param opts [Hash] The options hash.
      # @return [void]
      def build_nested_routes(nested_path, opts)
        push_scope(path: '/:id') do
          push_scope(path: "/#{nested_path}") do
            add_nested_routes(nested_path, opts)
          end
        end
      end

      # Add routes for a nested resource.
      #
      # @param nested_path [String] The path for the nested resource.
      # @param opts [Hash] The options hash.
      # @return [void]
      def add_nested_routes(nested_path, opts)
        add_route('',                 build_route_options(opts, :get,    "#{nested_path}#index"))
        add_route('/new',             build_route_options(opts, :get,    "#{nested_path}#new"))
        add_route('',                 build_route_options(opts, :post,   "#{nested_path}#create"))
        add_route('/:nested_id',      build_route_options(opts, :get,    "#{nested_path}#show"))
        add_route('/:nested_id/edit', build_route_options(opts, :get,    "#{nested_path}#edit"))
        add_route('/:nested_id',      opts.merge(via: %i[put patch], to: "#{nested_path}#update"))
        add_route('/:nested_id',      build_route_options(opts, :delete, "#{nested_path}#destroy"))
      end
    end
  end
end
