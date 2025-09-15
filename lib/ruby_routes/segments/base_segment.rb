# frozen_string_literal: true

module RubyRoutes
  module Segments
    # BaseSegment
    #
    # Abstract superclass for all parsed route path segments.
    # Concrete subclasses implement:
    # - StaticSegment: literal path component
    # - DynamicSegment: parameter capture (e.g. :id)
    # - WildcardSegment: greedy capture (e.g. *path)
    #
    # Responsibilities shared by subclasses:
    # - Supplying a child node in the radix tree (ensure_child)
    # - Participating in traversal / matching (match)
    #
    # Subclasses must override #ensure_child and #match.
    #
    # @api internal
    class BaseSegment
      # @param raw_segment_text [String, Symbol, nil]
      def initialize(raw_segment_text = nil)
        @raw_text = raw_segment_text.to_s if raw_segment_text
        @param_name = nil
      end

      # Get the parameter name for this segment (if any).
      #
      # @return [String, nil]
      def param_name
        @param_name
      end

      # Indicates whether this segment is a wildcard (greedy) segment.
      #
      # @return [Boolean]
      def wildcard?
        false
      end

      # Ensure the proper child node exists beneath +parent_node+ for this segment
      # and return it.
      #
      # @param parent_node [Object] radix tree node (implementation-specific)
      # @return [Object] the (possibly newly-created) child node
      # @raise [NotImplementedError] when not overridden
      def ensure_child(parent_node)
        raise NotImplementedError, "#{self.class}#ensure_child must be implemented"
      end

      # Attempt to match this segment during traversal.
      #
      # @param current_node [Object] the current radix node
      # @param incoming_segment_text [String] the path component being matched
      # @param _segment_index [Integer] index of the component in the path (unused here)
      # @param _all_segments [Array<String>] full list of segments (unused here)
      # @param _captured_params [Hash, nil] params hash to populate (unused here)
      # @return [Array<(Object, Boolean)>] [next_node, stop_traversal]
      # @raise [NotImplementedError] when not overridden
      def match(current_node, incoming_segment_text, _segment_index, _all_segments, _captured_params)
        raise NotImplementedError, "#{self.class}#match must be implemented"
      end
    end
  end
end
