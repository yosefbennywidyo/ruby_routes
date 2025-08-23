# frozen_string_literal: true

require_relative '../constant'

module RubyRoutes
  class RadixTree
    # Finder module for traversing the RadixTree and matching routes.
    # Handles path normalization, segment traversal, and parameter extraction.
    #
    # @module RubyRoutes::RadixTree::Finder
    module Finder
      private

      # Finds a route handler for the given path and HTTP method.
      #
      # @param path_input [String] the input path to match
      # @param method_input [String, Symbol] the HTTP method
      # @param params_out [Hash] optional output hash for captured parameters
      # @return [Array] [handler, params] or [nil, params] if no match
      def find(path_input, method_input, params_out = {})
        path = path_input.to_s
        method = normalize_http_method(method_input)
        return root_match(method, params_out) if path.empty? || path == RubyRoutes::Constant::ROOT_PATH

        segments = split_path_cached(path)
        return [nil, params_out || {}] if segments.empty?

        params = params_out || {}
        state = traversal_state

        perform_traversal(segments, state, method, params)

        finalize_success(state, method, params)
      end

      # Initializes the traversal state for route matching.
      #
      # @return [Hash] state hash with :current, :best_node, :best_params, :matched
      def traversal_state
        {
          current: @root_node,
          best_node: nil,
          best_params: nil,
          matched: false # Track if any segment was successfully matched
        }
      end

      # Performs traversal through path segments to find a matching route.
      #
      # @param segments [Array<String>] path segments
      # @param state [Hash] traversal state
      # @param method [String] normalized HTTP method
      # @param params [Hash] parameters hash
      def perform_traversal(segments, state, method, params)
        segments.each_with_index do |segment, index|
          next_node, stop = traverse_for_segment(state[:current], segment, index, segments, params)
          return finalize_on_fail(state, method, params) unless next_node

          state[:current] = next_node
          state[:matched] = true # Set matched to true if at least one segment matched
          record_candidate(state, method, params) if endpoint_with_method?(state[:current], method)
          break if stop
        end
      end

      # Traverses to the next node for a given segment.
      #
      # @param node [Node] current node
      # @param segment [String] current segment
      # @param index [Integer] segment index
      # @param segments [Array<String>] all segments
      # @param params [Hash] parameters hash
      # @return [Array] [next_node, stop_traversal]
      def traverse_for_segment(node, segment, index, segments, params)
        node.traverse_for(segment, index, segments, params)
      end

      # Records the current node as a candidate match.
      #
      # @param state [Hash] traversal state
      # @param _method [String] HTTP method (unused)
      # @param params [Hash] parameters hash
      def record_candidate(state, _method, params)
        state[:best_node] = state[:current]
        state[:best_params] = params.dup
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
      # @return [Array] [handler, params] or [nil, params]
      def finalize_on_fail(state, method, params)
        if state[:best_node]
          handler = state[:best_node].handlers[method]
          return constraints_pass?(handler, state[:best_params]) ? [handler, state[:best_params]] : [nil, params]
        end
        [nil, params]
      end

      # Finalizes the result after successful traversal.
      #
      # @param state [Hash] traversal state
      # @param method [String] HTTP method
      # @param params [Hash] parameters hash
      # @return [Array] [handler, params] or [nil, params]
      def finalize_success(state, method, params)
        node = state[:current]
        if endpoint_with_method?(node, method) && state[:matched]
          handler = node.handlers[method]
          return [handler, params] if constraints_pass?(handler, params)
        end
        # For non-matching paths, return nil
        [nil, params]
      end

      # Falls back to the best candidate if no exact match.
      #
      # @param state [Hash] traversal state
      # @param method [String] HTTP method
      # @param params [Hash] parameters hash
      # @return [Array] [handler, params] or [nil, params]
      def fallback_candidate(state, method, params)
        if state[:best_node] && state[:best_node] != @root_node
          handler = state[:best_node].handlers[method]
          return [handler, state[:best_params]] if handler && constraints_pass?(handler, state[:best_params])
        end
        [nil, params]
      end

      # Handles matching for the root path.
      #
      # @param method [String] HTTP method
      # @param params_out [Hash] parameters hash
      # @return [Array] [handler, params] or [nil, params]
      def root_match(method, params_out)
        if @root_node.is_endpoint && (handler = @root_node.handlers[method])
          [handler, params_out || {}]
        else
          [nil, params_out || {}]
        end
      end

      # Checks if constraints pass for the handler.
      #
      # @param handler [Object] the route handler
      # @param params [Hash] parameters hash
      # @return [Boolean] true if constraints pass
      def constraints_pass?(handler, params)
        check_constraints(handler, params&.dup || {})
      end
    end
  end
end
