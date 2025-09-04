# frozen_string_literal: true

require_relative '../constant'

module RubyRoutes
  class RadixTree
    # Finder module for traversing the RadixTree and finding routes.
    # Handles path normalization, segment traversal, and parameter extraction.
    module Finder

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

      private

      # Finds a route handler for the given path and HTTP method.
      #
      # @param path_input [String] the input path to match
      # @param method_input [String, Symbol] the HTTP method
      # @param params_out [Hash] optional output hash for captured parameters
      # @return [Array] [handler, params] or [nil, params] if no match
      def find(path_input, method_input, params_out = nil)
        path = path_input.to_s
        method = normalize_http_method(method_input)
        return root_match(method, params_out) if path.empty? || path == RubyRoutes::Constant::ROOT_PATH

        segments = split_path_cached(path)
        return [nil, params_out || {}] if segments.empty?

        params = params_out || {}
        state = traversal_state
        captured_params = {}

        result = perform_traversal(segments, state, method, params, captured_params)
        return result unless result.nil?

        finalize_success(state, method, params, captured_params)
      end

      # Initializes the traversal state for route matching.
      #
      # @return [Hash] state hash with :current, :best_node, :best_params, :best_captured, :matched
      def traversal_state
        {
          current: @root,
          best_node: nil,
          best_params: nil,
          best_captured: nil,
          matched: false # Track if any segment was successfully matched
        }
      end

      # Performs traversal through path segments to find a matching route.
      #
      # @param segments [Array<String>] path segments
      # @param state [Hash] traversal state
      # @param method [String] normalized HTTP method
      # @param params [Hash] parameters hash
      # @param captured_params [Hash] hash to collect captured parameters
      # @return [nil, Array] nil if traversal succeeds, Array from finalize_on_fail if traversal fails
      def perform_traversal(segments, state, method, params, captured_params)
        segments.each_with_index do |segment, index|
          next_node, stop = traverse_for_segment(state[:current], segment, index, segments, params, captured_params)
          return finalize_on_fail(state, method, params, captured_params) unless next_node

          state[:current] = next_node
          state[:matched] = true # Set matched to true if at least one segment matched
          record_candidate(state, method, params, captured_params) if endpoint_with_method?(state[:current], method)
          break if stop
        end
        nil # Return nil to indicate successful traversal
      end

      # Traverses to the next node for a given segment.
      #
      # @param node [Node] current node
      # @param segment [String] current segment
      # @param index [Integer] segment index
      # @param segments [Array<String>] all segments
      # @param params [Hash] parameters hash
      # @param captured_params [Hash] hash to collect captured parameters
      # @return [Array] [next_node, stop_traversal, segment_captured]
      def traverse_for_segment(node, segment, index, segments, params, captured_params)
        next_node, stop, segment_captured = node.traverse_for(segment, index, segments, params)
        if segment_captured
          params.merge!(segment_captured)  # Merge into running params hash at each step
          captured_params.merge!(segment_captured)  # Keep for best candidate consistency
        end
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
        state[:best_params] = params.dup
        state[:best_captured] = captured_params.dup
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
        result = finalize_match(state[:current], method, params, captured_params)
        return result if result[0]

        # Try best candidate if current failed
        if state[:best_node]
          best_params = state[:best_params] || params
          best_captured = state[:best_captured] || captured_params
          finalize_match(state[:best_node], method, best_params, best_captured)
        else
          result
        end
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
          if check_constraints(handler, params)
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
          [handler, params_out || {}]
        else
          [nil, params_out || {}]
        end
      end

      # Applies captured parameters to the final params hash.
      #
      # @param params [Hash] the final parameters hash
      # @param captured_params [Hash] captured parameters from traversal
      def apply_captured_params(params, captured_params)
        params.merge!(captured_params) if captured_params && !captured_params.empty?
      end
    end
  end
end
