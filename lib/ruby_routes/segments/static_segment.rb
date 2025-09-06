# frozen_string_literal: true

module RubyRoutes
  module Segments
    # StaticSegment
    #
    # Represents a literal (non-parameter) segment in a route path.
    # Example: "users" in "/users/:id".
    #
    # Responsibilities:
    # - Ensures a static child node exists under the current radix node
    #   keyed by the literal segment text.
    # - During traversal (#match), returns the child node for the incoming
    #   path component if it exists.
    #
    # Matching Behavior:
    # - Succeeds only when the exact literal exists as a child.
    # - Never captures parameters (no changes to params hash).
    # - Never stops traversal early (second tuple element = false).
    #
    # Returned tuple from #match:
    #   [next_node, stop_traversal_flag]
    #
    # @api internal
    class StaticSegment < BaseSegment
      # @param raw_segment_text [String] literal segment token
      def initialize(raw_segment_text)
        super(raw_segment_text)
        @literal_text = raw_segment_text.freeze
      end

      # Ensure a static child node for this literal under +parent_node+.
      #
      # @param parent_node [Object] radix tree node
      # @return [Object] the static child node
      def ensure_child(parent_node)
        parent_node.static_children[@literal_text] ||= Node.new
        parent_node.static_children[@literal_text]
      end

      # Attempt to match this literal segment.
      #
      # @param current_node [Object] current radix node
      # @param incoming_segment_text [String] segment from request path
      # @param _segment_index [Integer] (unused)
      # @param _all_segments [Array<String>] (unused)
      # @param _extracted_params [Hash] (unused, no params captured)
      # @return [Array<(Object, Boolean)>] [next_node_or_nil, stop_traversal=false]
      def match(current_node, incoming_segment_text, _segment_index, _all_segments, _extracted_params)
        [current_node.static_children[incoming_segment_text], false]
      end
    end
  end
end
