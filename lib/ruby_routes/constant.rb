require_relative 'segments/base_segment'
require_relative 'segments/dynamic_segment'
require_relative 'segments/static_segment'
require_relative 'segments/wildcard_segment'
require_relative 'lru_strategies/hit_strategy'
require_relative 'lru_strategies/miss_strategy'

module RubyRoutes
  # Constant
  #
  # Central registry for lightweight immutable structures and singleton
  # strategy objects used across routing components. Centralization keeps
  # hot path code free of repeated allocations and magic numbers.
  #
  # Responsibilities:
  # - Map first byte (ASCII) of a raw segment to its Segment subclass.
  # - Provide lambda matchers for radix traversal (legacy / fallback).
  # - Expose singleton LRU strategy objects (hit / miss).
  # - Build compact Hash descriptors for parsed route path segments.
  #
  # Design Notes:
  # - Numeric keys (42, 58) are ASCII codes for '*' and ':' allowing
  #   O(1) dispatch without extra string comparisons.
  # - Descriptor factories return frozen data to enable safe reuse.
  #
  # @api internal
  module Constant
    # Maps a segment's first byte (ASCII) to a Segment class.
    #
    # Keys:
    # 42 ('*')  -> Wildcard
    # 58 (':')  -> Dynamic
    # :default  -> Static
    SEGMENTS = {
      42 => RubyRoutes::Segments::WildcardSegment,   # '*'
      58 => RubyRoutes::Segments::DynamicSegment,    # ':'
      :default => RubyRoutes::Segments::StaticSegment
    }.freeze

    # Legacy lambda-based segment matchers (kept for compatibility / fallback).
    # Each lambda returns [next_node, stop_traversal] or nil when no match.
    SEGMENT_MATCHERS = {
      static: lambda do |node, segment, _idx, _segments, _params|
        child = node.static_children[segment]
        child ? [child, false] : nil
      end,

      dynamic: lambda do |node, segment, _idx, _segments, params|
        return nil unless node.dynamic_child
        next_node = node.dynamic_child
        params[next_node.param_name.to_s] = segment if params && next_node.param_name
        [next_node, false]
      end,

      wildcard: lambda do |node, _segment, idx, segments, params|
        return nil unless node.wildcard_child
        next_node = node.wildcard_child
        params[next_node.param_name.to_s] = segments[idx..-1].join('/') if params && next_node.param_name
        [next_node, true]
      end,

      # Default → no match
      default: lambda { |_node, _segment, _idx, _segments, _params| nil }
    }.freeze

    # Singleton instances to avoid per-cache strategy allocations.
    LRU_HIT_STRATEGY  = RubyRoutes::LruStrategies::HitStrategy.new.freeze
    LRU_MISS_STRATEGY = RubyRoutes::LruStrategies::MissStrategy.new.freeze

    # Factories producing compact immutable descriptors for segments used
    # during route compilation (faster than instantiating many objects).
    #
    # Returns Hash with keys:
    # - type: :static | :param | :splat
    # - value (for static) or name (for dynamic/splat)
    DESCRIPTOR_FACTORIES = {
      42 => ->(s) {
        name = s[1..-1]
        { type: :splat, name: (name.nil? || name.empty? ? 'splat' : name).freeze }
      }, # '*'
      58 => ->(s) { { type: :param,  name: s[1..-1].freeze } },              # ':'
      :default => ->(s) { { type: :static, value: s.freeze } }
    }.freeze

    # Build a descriptor Hash for a raw segment string.
    #
    # @param raw [String, #to_s]
    # @return [Hash] descriptor (frozen values inside)
    #
    # @example
    #   Constant.segment_descriptor(":id") # => { type: :param, name: "id" }
    def self.segment_descriptor(raw)
      segment_string = raw.to_s
      dispatch_key   = segment_string.empty? ? :default : segment_string.getbyte(0)
      factory        = DESCRIPTOR_FACTORIES[dispatch_key] || DESCRIPTOR_FACTORIES[:default]
      factory.call(segment_string)
    end
  end
end
