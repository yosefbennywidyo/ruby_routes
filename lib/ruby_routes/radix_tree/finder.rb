# frozen_string_literal: true

require_relative '../constant'

module RubyRoutes
  class RadixTree
    module Finder
      private

      def find(path_input, method_input, params_out = {})
        path   = path_input.to_s
        method = normalize_http_method(method_input)
        return root_match(method, params_out) if path.empty? || path == RubyRoutes::Constant::ROOT_PATH

        segments = split_path_cached(path)
        return [nil, params_out || {}] if segments.empty?

        params = params_out || {}
        state  = traversal_state

        segments.each_with_index do |seg, idx|
            next_node, stop = traverse_for_segment(state[:current], seg, idx, segments, params)
            unless next_node
              return finalize_on_fail(state, method, params)
            end
            state[:current] = next_node
            record_candidate(state, method, params) if endpoint_with_method?(state[:current], method)
            break if stop
        end

        finalize_success(state, method, params)
      end

      def traversal_state
        {
          current: @root_node,
          best_node: nil,
          best_params: nil
        }
      end

      def traverse_for_segment(node, seg, idx, segments, params)
        node.traverse_for(seg, idx, segments, params)
      end

      def record_candidate(state, method, params)
        state[:best_node]   = state[:current]
        state[:best_params] = params.dup
      end

      def endpoint_with_method?(node, method)
        node.is_endpoint && node.handlers[method]
      end

      def finalize_on_fail(state, method, params)
        if state[:best_node]
          handler = state[:best_node].handlers[method]
          return constraints_pass?(handler, state[:best_params]) ? [handler, state[:best_params]] : [nil, params]
        end
        [nil, params]
      end

      def finalize_success(state, method, params)
        node = state[:current]
        if endpoint_with_method?(node, method)
          handler = node.handlers[method]
          return [handler, params] if constraints_pass?(handler, params)
          return fallback_candidate(state, method, params)
        end
        fallback_candidate(state, method, params)
      end

      def fallback_candidate(state, method, params)
        if state[:best_node]
          handler = state[:best_node].handlers[method]
          return [handler, state[:best_params]] if handler && constraints_pass?(handler, state[:best_params])
        end
        [nil, params]
      end

      def root_match(method, params_out)
        if @root_node.is_endpoint && (h = @root_node.handlers[method])
          [h, params_out || {}]
        else
          [nil, params_out || {}]
        end
      end

      def constraints_pass?(handler, params)
        check_constraints(handler, params)
      end
    end
  end
end
