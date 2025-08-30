# frozen_string_literal: true

require_relative 'segments/base_segment'
require_relative 'segments/dynamic_segment'
require_relative 'segments/static_segment'
require_relative 'segments/wildcard_segment'
require_relative 'constant'

module RubyRoutes
  # Segment
  #
  # Factory wrapper that selects the correct concrete Segment subclass
  # (Static / Dynamic / Wildcard) based on the first character of a raw
  # path token:
  # - ":" → DynamicSegment (named param, e.g. :id)
  # - "*" → WildcardSegment (greedy splat, e.g. *path)
  # - otherwise → StaticSegment (literal text)
  #
  # It delegates byte‑based dispatch to RubyRoutes::Constant::SEGMENTS
  # for O(1) lookup without multiple string comparisons.
  #
  # @api internal
  class Segment
    # Build an appropriate segment instance for the provided token.
    #
    # @param text [String, Symbol, #to_s] raw segment token
    # @return [RubyRoutes::Segments::BaseSegment]
    #
    # @example
    #   Segment.for(":id")    # => DynamicSegment
    #   Segment.for("*files") # => WildcardSegment
    #   Segment.for("users")  # => StaticSegment
    def self.for(text)
      segment_text  = text.to_s
      segment_key   = segment_text.empty? ? :default : segment_text.getbyte(0)
      segment_class = RubyRoutes::Constant::SEGMENTS[segment_key] || RubyRoutes::Constant::SEGMENTS[:default]
      segment_class.new(segment_text)
    end
  end
end
