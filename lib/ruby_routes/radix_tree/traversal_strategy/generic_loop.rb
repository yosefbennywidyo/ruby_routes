# frozen_string_literal: true

require_relative 'base'

module RubyRoutes
  class RadixTree
    module TraversalStrategy
      # Traversal strategy using a generic loop, ideal for longer paths (4+ segments).
      class GenericLoop < Base
        def execute(segments, state, method, params, captured_params)
          segments.each_with_index do |segment, index|
            next_node, stop = @finder.send(:traverse_for_segment, state[:current], segment, index, segments, params, captured_params)
            return @finder.send(:finalize_on_fail, state, method, params, captured_params) unless next_node

            state[:current] = next_node
            state[:matched] = true
            @finder.send(:record_candidate, state, method, params, captured_params) if @finder.send(:endpoint_with_method?, state[:current], method)
            break if stop
          end
          nil # Signal successful traversal
        end
      end
    end
  end
end
