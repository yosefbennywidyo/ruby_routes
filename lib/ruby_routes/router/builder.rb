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
        recorded_calls.each do |(method_name, arguments, definition_block)|
          router.public_send(method_name, *arguments, &definition_block)
        end
        router.finalize!
        router
      end
    end
  end
end
