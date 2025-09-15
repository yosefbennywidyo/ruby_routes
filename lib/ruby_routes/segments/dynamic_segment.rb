# frozen_string_literal: true

module RubyRoutes
  module Segments
    # DynamicSegment
    #
    # Represents a single dynamic (named) path component in a route
    # definition (e.g. ":id" in "/users/:id").
    #
    # Responsibilities:
    # - Ensures a dynamic_child node exists in the radix tree for traversal.
    # - On match, captures the actual segment text into the params hash
    #   using the parameter name (without the leading colon).
    #
    # Matching Behavior:
    # - Succeeds if the current radix node has a dynamic_child.
    # - Does NOT stop traversal (returns false as second tuple value).
    #
    # Returned tuple from #match:
    #   [next_node, stop_traversal_flag]
    #
    # @api internal
    class DynamicSegment < BaseSegment
      # @param raw_segment_text [String] raw token (e.g. ":id")
      def initialize(raw_segment_text)
        super(raw_segment_text)
        @param_name = raw_segment_text[1..]
      end

      # Ensure a dynamic child node under +parent_node+ and assign the
      # parameter name to that node for later extraction.
      #
      # @param parent_node [Object] radix tree node
      # @return [Object] the dynamic child node
      def ensure_child(parent_node)
        parent_node.dynamic_child ||= Node.new
        dynamic_child_node = parent_node.dynamic_child
        dynamic_child_node.param_name ||= @param_name
        dynamic_child_node
      end

      # Attempt to match this segment during traversal.
      #
      # @param current_node [Object] current radix node
      # @param incoming_segment_text [String] actual path segment from request
      # @param _segment_index [Integer] (unused)
      # @param _all_segments [Array<String>] (unused)
      # @param captured_params [Hash] params hash to populate
      # @return [Array<(Object, Boolean)>] [next_node, stop_traversal=false]
      def match(current_node, incoming_segment_text, _segment_index, _all_segments, captured_params)
        return [nil, false] unless current_node.dynamic_child

        dynamic_child_node = current_node.dynamic_child
        captured_params[dynamic_child_node.param_name.to_s] = incoming_segment_text if captured_params
        [dynamic_child_node, false]
      end
    end
  end
end
