# frozen_string_literal: true

require_relative '../constant'
module RubyRoutes
  class Router
    # Builder
    #
    # Records routing DSL invocations without mutating a live Router.
    # Later, #build replays the recorded calls on a fresh Router,
    # finalizes it (immutability), and returns the frozen instance.
    #
    # Benefits:
    # - Decouples route declaration time from Router instantiation
    # - Enables reuse (same blueprint -> multiple routers)
    # - Safe to construct on boot and share across threads after build
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
    class Builder
      # Array of recorded calls: [method_symbol, args_array, block]
      # @return [Array<Array(Symbol, Array, Proc|NilClass)>]
      attr_reader :recorded_calls

      # @yield Runs the routing DSL in a recording context (optional)
      def initialize(&definition_block)
        @recorded_calls = []
        instance_eval(&definition_block) if definition_block
      end

      # ---- DSL Recording -------------------------------------------------
      RubyRoutes::Constant::RECORDED_METHODS.each do |method_name|
        next if %i[build initialize recorded_calls].include?(method_name)

        define_method(method_name) do |*arguments, &definition_block|
          @recorded_calls << [method_name, arguments, definition_block]
          nil
        end
      end

      # Replay recorded calls on a fresh Router, finalize, return it.
      #
      # @return [RubyRoutes::Router] finalized router
      def build
        router = Router.new
        allowlist = RubyRoutes::Constant::RECORDED_METHODS

        recorded_calls.each do |(method_name, arguments, definition_block)|
          # Security: only allow predefined DSL methods (prevents arbitrary method execution)
          raise ArgumentError, "Disallowed DSL method: #{method_name.inspect}" unless allowlist.include?(method_name)

          # (Optional) shallow dup args to avoid later mutation side‑effects
          safe_args = arguments.map do |argument|
            argument.is_a?(String) || argument.is_a?(Numeric) || argument.is_a?(Symbol) ? argument : argument.dup
          rescue StandardError
            argument
          end

          case method_name
          when :get, :post, :put, :patch, :delete, :head, :options
            router.send(method_name, *safe_args, &definition_block)
          when :match, :root, :resources, :resource
            router.send(method_name, *safe_args, &definition_block)
          when :namespace, :scope, :constraints, :defaults
            router.send(method_name, *safe_args, &definition_block)
          when :mount, :concern, :concerns
            router.send(method_name, *safe_args, &definition_block)
          else
            # This shouldn't be reached due to allowlist check above
            raise ArgumentError, "Unsupported DSL method: #{method_name.inspect}"
          end
        end

        router.finalize!
        router
      end
    end
  end
end
