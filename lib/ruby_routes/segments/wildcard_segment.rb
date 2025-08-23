# frozen_string_literal: true

module RubyRoutes
  module Segments
    # WildcardSegment
    #
    # Represents a greedy (splat) segment in a route definition (e.g. "*path").
    # Captures the remainder of the request path (including embedded slashes)
    # starting at its position and stores it under the parameter name
    # (text after the asterisk) or "splat" if none provided.
    #
    # Matching Behavior:
    # - Succeeds only if the current radix node has a +wildcard_child+.
    # - Consumes all remaining segments and stops traversal (second tuple true).
    #
    # Returned tuple from #match:
    #   [next_node, stop_traversal_flag=true]
    #
    # @api internal
    class WildcardSegment < BaseSegment
      # Correctly derive parameter name for wildcard splats.
      #
      # "*photos"  -> "photos"
      # "*"        -> "splat"   (previous code produced "" and never fell back)
      #
      # Also ensures @raw_text is assigned by delegating to BaseSegment#initialize.
      # @param raw_segment_text [String] raw token (e.g. "*path" or "*")
      def initialize(raw_segment_text)
        super(raw_segment_text)
        tail = raw_segment_text && raw_segment_text[1..]
        tail = nil if tail == '' # treat empty substring as absent
        @param_name = tail || 'splat'
      end

      # Ensure a wildcard child node on +parent_node+ and assign param name.
      #
      # @param parent_node [Object]
      # @return [Object] wildcard child node
      def ensure_child(parent_node)
        parent_node.wildcard_child ||= Node.new
        wildcard_child_node = parent_node.wildcard_child
        wildcard_child_node.param_name = @param_name
        wildcard_child_node
      end

      # @return [Boolean] always true for wildcard segment
      def wildcard?
        true
      end

      # Attempt to match / consume remaining path.
      #
      # @param current_node [Object] current radix node
      # @param _unused_literal [String] (unused)
      # @param segment_index [Integer] index where wildcard appears
      # @param all_path_segments [Array<String>] all request segments
      # @param captured_params [Hash] params hash to populate
      # @return [Array<(Object, Boolean)>] [wildcard_child_node_or_nil, stop_traversal_flag]
      def match(current_node, _unused_literal, segment_index, all_path_segments, captured_params)
        return [nil, false] unless current_node.wildcard_child

        wildcard_child_node = current_node.wildcard_child
        if captured_params
          remaining_path = all_path_segments[segment_index..].join('/')
          captured_params[wildcard_child_node.param_name.to_s] = remaining_path
        end
        [wildcard_child_node, true]
      end
    end
  end
end
