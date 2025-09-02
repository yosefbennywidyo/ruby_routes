# frozen_string_literal: true

require_relative '../constant'

module RubyRoutes
  class Router
    # BuildHelpers
    #
    # Small, focused utilities used while constructing routes and routers.
    module BuildHelpers
      # Build the router from recorded calls.
      #
      # This method creates a new `Router` instance, validates the recorded calls,
      # finalizes the router (making it immutable), and returns the frozen instance.
      #
      # @return [Router] The finalized router.
      def build
        router = Router.new
        validate_calls(@recorded_calls)
        router.finalize!
        router
      end

      # Build route options.
      #
      # This method creates a copy of the base options and conditionally adds
      # the `:via` and `:to` keys if they are not already present or need to be overridden.
      #
      # @param base_options [Hash] The base options for the route.
      # @param via_sym [Symbol, nil] The HTTP method (e.g., `:get`, `:post`).
      # @param to_string [String, nil] The controller#action string (e.g., `"users#index"`).
      # @return [Hash] The updated route options.
      def build_route_options(base_options, via_sym = nil, to_string = nil)
        force_via = !via_sym.nil? && base_options[:via] != via_sym
        add_to    = !to_string.nil? && !base_options.key?(:to)
        return base_options unless force_via || add_to

        options_copy = base_options.dup
        options_copy[:via] = via_sym if force_via
        options_copy[:to]  = to_string if add_to
        options_copy
      end

      # Helper: Build collection routes inside a resource scope.
      #
      # This method defines routes for collection-level actions (e.g., `index`, `new`, `create`)
      # within the scope of a resource.
      #
      # @param opts [Hash] The options to apply to the routes.
      # @param to_index [String] The controller#action string for the `index` action.
      # @param to_new [String] The controller#action string for the `new` action.
      # @param to_create [String] The controller#action string for the `create` action.
      # @return [void]
      def build_collection_routes(opts, to_index, to_new, to_create)
        add_route('',     build_route_options(opts, :get,  to_index))
        add_route('/new', build_route_options(opts, :get,  to_new))
        add_route('',     build_route_options(opts, :post, to_create))
      end

      # Helper: Build member routes inside a resource scope.
      #
      # This method defines routes for member-level actions (e.g., `show`, `edit`, `update`, `destroy`)
      # within the scope of a resource.
      #
      # @param opts [Hash] The options to apply to the routes.
      # @param to_show [String] The controller#action string for the `show` action.
      # @param to_edit [String] The controller#action string for the `edit` action.
      # @param to_update [String] The controller#action string for the `update` action.
      # @param to_destroy [String] The controller#action string for the `destroy` action.
      # @return [void]
      def build_member_routes(opts, to_show, to_edit, to_update, to_destroy)
        add_route('/:id',      build_route_options(opts, :get,    to_show))
        add_route('/:id/edit', build_route_options(opts, :get,    to_edit))
        add_route('/:id',      opts.merge(via: %i[put patch], to: to_update))
        add_route('/:id',      build_route_options(opts, :delete, to_destroy))
      end

      private

      # Validate the recorded calls.
      #
      # This method ensures that all recorded calls use valid router methods
      # as defined in `RubyRoutes::Constant::RECORDED_METHODS`.
      #
      # @param recorded_calls [Array<Array(Symbol, Array, Proc|NilClass)>]
      #   The recorded calls to validate.
      # @raise [ArgumentError] If any recorded call uses an invalid method.
      # @return [void]
      def validate_calls(recorded_calls)
        allowed_router_methods = RubyRoutes::Constant::RECORDED_METHODS
        recorded_calls.each do |(router_method, _arguments, _definition_block)|
          unless router_method.is_a?(Symbol) && allowed_router_methods.include?(router_method)
            raise ArgumentError, "Invalid router method: #{router_method.inspect}"
          end
        end
      end
    end
  end
end
