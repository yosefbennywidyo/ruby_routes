# frozen_string_literal: true

require_relative 'traversal_strategy/base'
require_relative 'traversal_strategy/generic_loop'
require_relative 'traversal_strategy/unrolled'

module RubyRoutes
  class RadixTree
    # This module encapsulates the different strategies for traversing the RadixTree.
    # It provides a factory to select the appropriate strategy based on path length.
    module TraversalStrategy
      # Selects the appropriate traversal strategy based on the number of segments.
      #
      # @param segment_count [Integer] The number of segments in the path.
      # @param finder [RubyRoutes::RadixTree::Finder] The finder instance.
      # @return [Base] An instance of a traversal strategy.
      def self.for(segment_count, finder)
        if segment_count <= 3
          OptimizedUnrolled.new(finder)
        else
          GenericLoop.new(finder)
        end
      end
    end
  end
end
