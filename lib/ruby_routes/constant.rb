require_relative 'segments/dynamic_segment'
require_relative 'segments/static_segment'
require_relative 'segments/wildcard_segment'
require_relative 'lru_strategies/hit_strategy'
require_relative 'lru_strategies/miss_strategy'

module RubyRoutes
  module Constant
    SEGMENTS = {
      42 => RubyRoutes::Segments::WildcardSegment,   # '*'
      58 => RubyRoutes::Segments::DynamicSegment,    # ':'
      :default => RubyRoutes::Segments::StaticSegment
    }.freeze

    SEGMENT_MATCHERS = {
      static: lambda do |node, segment, _idx, _segments, _params|
        child = node.static_children[segment]
        child ? [child, false] : nil
      end,

      dynamic: lambda do |node, segment, _idx, _segments, params|
        return nil unless node.dynamic_child
        nxt = node.dynamic_child
        params[nxt.param_name.to_s] = segment if params && nxt.param_name
        [nxt, false]
      end,

      wildcard: lambda do |node, _segment, idx, segments, params|
        return nil unless node.wildcard_child
        nxt = node.wildcard_child
        params[nxt.param_name.to_s] = segments[idx..-1].join('/') if params && nxt.param_name
        [nxt, true]
      end,

      # default returns nil (no match). RadixTree#find will then return [nil, {}].
      default: lambda { |_node, _segment, _idx, _segments, _params| nil }
    }.freeze

    # singleton instances to avoid per-LRU allocations
    LRU_HIT_STRATEGY = RubyRoutes::LruStrategies::HitStrategy.new.freeze
    LRU_MISS_STRATEGY = RubyRoutes::LruStrategies::MissStrategy.new.freeze

    # Descriptor factories for segment classification (O(1) dispatch by first byte).
    DESCRIPTOR_FACTORIES = {
      42 => ->(s) { { type: :splat,  name: (s[1..-1] || 'splat').freeze } }, # '*'
      58 => ->(s) { { type: :param,  name:   s[1..-1].freeze } },             # ':'
      :default => ->(s) { { type: :static, value:  s.freeze } }  # Intern static values
    }.freeze

    def self.segment_descriptor(raw)
      s = raw.to_s
      key = s.empty? ? :default : s.getbyte(0)
      factory = DESCRIPTOR_FACTORIES[key] || DESCRIPTOR_FACTORIES[:default]
      factory.call(s)
    end
  end
end
