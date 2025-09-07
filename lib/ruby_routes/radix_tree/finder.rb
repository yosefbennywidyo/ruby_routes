# frozen_string_literal: true

require_relative '../constant'
require_relative 'traversal_strategy'

module RubyRoutes
  class RadixTree
    # Finder module for traversing the RadixTree and finding routes.
    # Handles path normalization, segment traversal, and parameter extraction.
    module Finder

      # Pre-allocated buffers to minimize object creation
      EMPTY_PARAMS = {}.freeze
      TRAVERSAL_STATE_TEMPLATE = {
        current: nil,
        best_node: nil,
        best_params: nil,
        best_captured: nil,
        matched: false
      }.freeze

      # Reusable hash for captured parameters to avoid repeated allocations
      PARAMS_BUFFER_KEY = :ruby_routes_finder_params_buffer
      CAPTURED_PARAMS_BUFFER_KEY = :ruby_routes_finder_captured_params_buffer
      STATE_BUFFER_KEY = :ruby_routes_finder_state_buffer

      # Evaluate constraint rules for a candidate route.
      #
      # @param route_handler [Object]
      # @param captured_params [Hash]
      # @return [Boolean]
      def check_constraints(route_handler, captured_params)
        return true unless route_handler.respond_to?(:validate_constraints_fast!)

        begin
          # Use a duplicate to avoid unintended mutation by validators.
          route_handler.validate_constraints_fast!(captured_params)
          true
        rescue RubyRoutes::ConstraintViolation
          false
        end
      end

      # Finds a route handler for the given path and HTTP method.
      #
      # @param path_input [String] the input path to match
      # @param method_input [String, Symbol] the HTTP method
      # @param params_out [Hash] optional output hash for captured parameters
      # @return [Array] [handler, params] or [nil, {}] if no match
      def find(path_input, http_method, params_out = nil)
        # Handle nil or empty path input
        return [nil, EMPTY_PARAMS] if path_input.nil?

        method = normalize_http_method(http_method)
        return root_match(method, params_out || EMPTY_PARAMS) if path_input.empty? || path_input == RubyRoutes::Constant::ROOT_PATH

        segments = split_path_cached(path_input)
        return [nil, EMPTY_PARAMS] if segments.empty?

        # Use thread-local, reusable hashes to avoid allocations
        params = acquire_params_buffer(params_out)
        state = acquire_state_buffer
        captured_params = acquire_captured_params_buffer

        result = perform_traversal(segments, state, method, params, captured_params)
        return result unless result.nil?

        finalize_success(state, method, params, captured_params)
      end

      # Initializes the traversal state for route matching.
      #
      # @return [Hash] state hash with :current, :best_node, :best_params, :best_captured, :matched
      def acquire_state_buffer
        state = Thread.current[STATE_BUFFER_KEY] ||= {}
        state.clear
        state[:current] = @root
        state
      end

      def acquire_params_buffer(initial_params)
        buffer = Thread.current[PARAMS_BUFFER_KEY] ||= {}
        buffer.clear
        buffer.merge!(initial_params) if initial_params
        buffer
      end

      def acquire_captured_params_buffer
        buffer = Thread.current[CAPTURED_PARAMS_BUFFER_KEY] ||= {}
        buffer.clear
        buffer
      end

      # Performs traversal through path segments to find a matching route.
      # Optimized for common cases of 1-3 segments.
      #
      # @param segments [Array<String>] path segments
      # @param state [Hash] traversal state
      # @param method [String] normalized HTTP method
      # @param params [Hash] parameters hash
      # @param captured_params [Hash] hash to collect captured parameters
      # @return [nil, Array] nil if traversal succeeds, Array from finalize_on_fail if traversal fails
      def perform_traversal(segments, state, method, params, captured_params) # rubocop:disable Metrics/AbcSize
        TraversalStrategy.for(segments.size, self).execute(segments, state, method, params, captured_params)
      end

      # Traverses to the next node for a given segment.
      #
      # @param node [Node] current node
      # @param segment [String] current segment
      # @param index [Integer] segment index
      # @param segments [Array<String>] all segments
      # @param params [Hash] parameters hash
      # @param captured_params [Hash] hash to collect captured parameters
      # @return [Array] [next_node, stop_traversal]
      def traverse_for_segment(node, segment, index, segments, params, captured_params)
        next_node, stop, segment_captured = node.traverse_for(segment, index, segments, params)
        merge_captured_params(params, captured_params, segment_captured)
        [next_node, stop]
      end

      # Records the current node as a candidate match.
      #
      # @param state [Hash] traversal state
      # @param _method [String] HTTP method (unused)
      # @param params [Hash] parameters hash
      # @param captured_params [Hash] captured parameters from traversal
      def record_candidate(state, _method, params, captured_params)
        state[:best_node] = state[:current]
        state[:best_params] = params
        state[:best_captured] = captured_params
      end

      # Checks if the node is an endpoint with a handler for the method.
      #
      # @param node [Node] the node to check
      # @param method [String] HTTP method
      # @return [Boolean] true if endpoint and handler exists
      def endpoint_with_method?(node, method)
        node.is_endpoint && node.handlers[method]
      end

      # Finalizes the result when traversal fails mid-path.
      #
      # @param state [Hash] traversal state
      # @param method [String] HTTP method
      # @param params [Hash] parameters hash
      # @param captured_params [Hash] captured parameters from traversal
      # @return [Array] [handler, params] or [nil, params]
      def finalize_on_fail(state, method, params, captured_params)
        best_params = state[:best_params] || params
        best_captured = state[:best_captured] || captured_params
        finalize_match(state[:best_node], method, best_params, best_captured)
      end

      # Finalizes the result after successful traversal.
      #
      # @param state [Hash] traversal state
      # @param method [String] HTTP method
      # @param params [Hash] parameters hash
      # @param captured_params [Hash] captured parameters from traversal
      # @return [Array] [handler, params] or [nil, params]
      def finalize_success(state, method, params, captured_params)
        handler, final_params = finalize_match(state[:current], method, params, captured_params)
        return [handler, final_params] if handler

        # Try best candidate if current failed
        if state[:best_node]
          best_params = state[:best_params] || params
          best_captured = state[:best_captured] || captured_params
          handler, final_params = finalize_match(state[:best_node], method, best_params, best_captured)
        end

        [handler, final_params]
      end

      # Falls back to the best candidate if no exact match.
      #
      # @param state [Hash] traversal state
      # @param method [String] HTTP method
      # @param params [Hash] parameters hash
      # @param captured_params [Hash] captured parameters from traversal
      # @return [Array] [handler, params] or [nil, params]


      # Common method to finalize a match attempt.
      # Assumes the node is already validated as an endpoint.
      #
      # @param node [Node] the node to check for a handler
      # @param method [String] HTTP method
      # @param params [Hash] parameters hash
      # @param captured_params [Hash] captured parameters from traversal
      # @return [Array] [handler, params] or [nil, params]
      def finalize_match(node, method, params, captured_params)
        # Apply captured params once at the beginning
        apply_captured_params(params, captured_params)

        if node && endpoint_with_method?(node, method)
          handler = node.handlers[method]
          if check_constraints(handler, captured_params)
            return [handler, params]
          end
        end
        # For non-matching paths, return nil
        [nil, params]
      end
      #
      # @param method [String] HTTP method
      # @param params_out [Hash] parameters hash
      # @return [Array] [handler, params] or [nil, params]
      def root_match(method, params_out)
        if @root.is_endpoint && (handler = @root.handlers[method])
          [handler, params_out]
        else
          [nil, EMPTY_PARAMS]
        end
      end

      # Applies captured parameters to the final params hash.
      #
      # @param params [Hash] the final parameters hash
      # @param captured_params [Hash] captured parameters from traversal
      def apply_captured_params(params, captured_params)
        # Merge all captured into final params without mutating captured_params
        merge_captured_params(params, captured_params, captured_params)
      end

      # Merges captured parameters into the parameter hashes.
      #
      # @param params [Hash] the main parameters hash
      # @param captured_params [Hash] the captured parameters hash
      # @param segment_captured [Hash] the newly captured parameters
      def merge_captured_params(params, captured_params, segment_captured)
        return if segment_captured.nil? || segment_captured.empty?

        params.merge!(segment_captured)
        captured_params.merge!(segment_captured)
      end
    end
  end
end
