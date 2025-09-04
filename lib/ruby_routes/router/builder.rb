# frozen_string_literal: true

require_relative '../constant'
require_relative 'build_helpers'

module RubyRoutes
  class Router
    # Builder
    #
    # Records routing DSL invocations without mutating a live Router.
    # Later, `#build` replays the recorded calls on a fresh Router,
    # finalizes it (immutability), and returns the frozen instance.
    #
    # Benefits:
    # - Decouples route declaration time from Router instantiation.
    # - Enables reuse (same blueprint -> multiple routers).
    # - Safe to construct on boot and share across threads after build.
    #
    # Usage:
    #   builder = RubyRoutes::Router::Builder.new do
    #     namespace :api do
    #       resources :users
    #     end
    #     get '/health', to: 'system#health'
    #   end
    #   router = builder.build  # finalized (router.frozen? == true)
    #
    # Supported DSL methods are mirrored here. Blocks are stored as Procs;
    # serialization of blocks is not supported.
    #
    # @api internal
    class Builder
      include RubyRoutes::Router::BuildHelpers

      # Array of recorded calls: [method_symbol, args_array, block].
      #
      # Each tuple contains:
      # - The method name (as a Symbol).
      # - The arguments (as an Array).
      # - The block (as a Proc or `nil`).
      #
      # @return [Array<Array(Symbol, Array, Proc|NilClass)>]
      #   A snapshot of the recorded calls to avoid external mutation.
      def recorded_calls
        # Deep-copy each recorded call’s args array and freeze the result to prevent mutation
        @recorded_calls
          .map { |(method_name, args, block)| [method_name, args.dup.freeze, block] }
          .freeze
      end

      # Initialize the Builder.
      #
      # This method initializes the `@recorded_calls` array and optionally
      # evaluates the provided block in the context of the Builder instance.
      #
      # @yield [definition_block] Runs the routing DSL in a recording context (optional).
      # @return [void]
      def initialize(&definition_block)
        @recorded_calls = []
        instance_eval(&definition_block) if definition_block
      end

      # ---- DSL Recording -------------------------------------------------
      # Dynamically define methods for all DSL methods specified in
      # `RubyRoutes::Constant::RECORDED_METHODS`. Each method records its
      # invocation (method name, arguments, and block) in `@recorded_calls`.
      #
      # The dynamically defined methods accept arbitrary arguments and an optional block,
      # which are recorded for later processing by the router.
      #
      # @return [nil]
      RubyRoutes::Constant::RECORDED_METHODS.each do |method_name|
        define_method(method_name) do |*arguments, &definition_block|
          @recorded_calls << [__method__, arguments, definition_block]
          nil
        end
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
