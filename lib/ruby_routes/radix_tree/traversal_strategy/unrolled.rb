# frozen_string_literal: true

require_relative 'base'

module RubyRoutes
  class RadixTree
    module TraversalStrategy
      # Traversal strategy using unrolled loops for common short paths (1-3 segments).
      # This provides a performance boost by avoiding loop overhead for the most frequent cases.
      class Unrolled < Base
        def execute(segments, state, method, params, captured_params)
          # This case statement manually unrolls the traversal loop for paths
          # with 1, 2, or 3 segments. The `TraversalStrategy.for` factory ensures
          # this strategy is only used for these lengths.
          case segments.size
          when 1
            outcome = traverse_segment(0, segments, state, method, params, captured_params)
            return @finder.finalize_on_fail(state, method, params, captured_params) if outcome == :fail
          when 2
            outcome = traverse_segment(0, segments, state, method, params, captured_params)
            return @finder.finalize_on_fail(state, method, params, captured_params) if outcome == :fail
            return nil if outcome == true  # stop
            outcome = traverse_segment(1, segments, state, method, params, captured_params)
            return @finder.finalize_on_fail(state, method, params, captured_params) if outcome == :fail
          when 3
            outcome = traverse_segment(0, segments, state, method, params, captured_params)
            return @finder.finalize_on_fail(state, method, params, captured_params) if outcome == :fail
            return nil if outcome == true  # stop
            outcome = traverse_segment(1, segments, state, method, params, captured_params)
            return @finder.finalize_on_fail(state, method, params, captured_params) if outcome == :fail
            return nil if outcome == true  # stop
            outcome = traverse_segment(2, segments, state, method, params, captured_params)
            return @finder.finalize_on_fail(state, method, params, captured_params) if outcome == :fail
          end
          nil # Return nil to indicate successful traversal
        end

        private

        # Traverses a single segment, updates state, and records candidate if applicable.
        # Returns true if traversal should stop (e.g., due to wildcard), false otherwise.
        def traverse_segment(index, segments, state, method, params, captured_params)
          next_node, stop = @finder.traverse_for_segment(state[:current], segments[index], index, segments, params, captured_params)
          return :fail unless next_node

          state[:current] = next_node
          state[:matched] = true
          @finder.record_candidate(state, method, params, captured_params) if @finder.endpoint_with_method?(state[:current], method)
          stop
        end
      end
    end
  end
end
