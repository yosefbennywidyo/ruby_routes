# frozen_string_literal: true

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
  # - Map the first byte (ASCII) of a raw segment to its Segment subclass.
  # - Provide lambda matchers for radix traversal (legacy/fallback).
  # - Expose singleton LRU strategy objects (hit/miss).
  # - Build compact Hash descriptors for parsed route path segments.
  #
  # Design Notes:
  # - Numeric keys (42, 58) are ASCII codes for '*' and ':' allowing
  #   O(1) dispatch without extra string comparisons.
  # - Descriptor factories return frozen data to enable safe reuse.
  #
  # @api internal
  module Constant
    # Shared, canonical root path constant (single source of truth).
    ROOT_PATH = '/'

    # Maps a segment's first byte (ASCII) to a Segment class.
    #
    # Keys:
    # - 42 ('*')  -> Wildcard
    # - 58 (':')  -> Dynamic
    # - :default  -> Static
    #
    # @return [Hash{Integer, Symbol => Class}]
    SEGMENTS = {
      42 => RubyRoutes::Segments::WildcardSegment,   # '*'
      58 => RubyRoutes::Segments::DynamicSegment,    # ':'
      :default => RubyRoutes::Segments::StaticSegment
    }.freeze

    # Legacy lambda-based segment matchers (kept for compatibility/fallback).
    #
    # Each lambda returns `[next_node, stop_traversal]` or `nil` when no match.
    #
    # @return [Hash{Symbol => Proc}]
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
        params[next_node.param_name.to_s] = segments[idx..].join('/') if params && next_node.param_name
        [next_node, true]
      end,

      default: ->(_node, _segment, _idx, _segments, _params) { nil }
    }.freeze

    # Singleton instances to avoid per-cache strategy allocations.
    #
    # @return [RubyRoutes::LruStrategies::HitStrategy, RubyRoutes::LruStrategies::MissStrategy]
    LRU_HIT_STRATEGY  = RubyRoutes::LruStrategies::HitStrategy.new.freeze
    LRU_MISS_STRATEGY = RubyRoutes::LruStrategies::MissStrategy.new.freeze

    # Factories producing compact immutable descriptors for segments used
    # during route compilation (faster than instantiating many objects).
    #
    # @return [Hash{Integer, Symbol => Proc}]
    DESCRIPTOR_FACTORIES = {
      42 => lambda { |s|
        name = s[1..]
        { type: :splat, name: (name.nil? || name.empty? ? 'splat' : name).freeze }
      }, # '*'
      58 => ->(s) { { type: :param, name: s[1..].freeze } }, # ':'
      :default => ->(s) { { type: :static, value: s.freeze } }
    }.freeze

    # Regex for unreserved characters (RFC 3986 subset).
    #
    # @return [Regexp]
    UNRESERVED_RE = /\A[a-zA-Z0-9\-._~]+\z/

    # Maximum size of the query parameter cache.
    #
    # This constant defines the maximum number of query strings that can be
    # cached for fast lookup. Once the cache reaches this size, the least
    # recently used entries will be evicted.
    #
    # @return [Integer]
    QUERY_CACHE_SIZE = 128

    # HTTP method constants.
    HTTP_GET     = 'GET'
    HTTP_POST    = 'POST'
    HTTP_PUT     = 'PUT'
    HTTP_PATCH   = 'PATCH'
    HTTP_DELETE  = 'DELETE'
    HTTP_HEAD    = 'HEAD'
    HTTP_OPTIONS = 'OPTIONS'

    # Empty constants for reuse.
    EMPTY_ARRAY  = [].freeze
    EMPTY_PAIR   = [EMPTY_ARRAY, EMPTY_ARRAY].freeze
    EMPTY_STRING = ''
    EMPTY_HASH   = {}.freeze

    # Maximum number of distinct (method, path) composite keys retained
    # before the oldest are overwritten in ring order.
    #
    # @return [Integer]
    REQUEST_KEY_CAPACITY = 4096

    # Supported DSL methods for route recording.
    #
    # @return [Array<Symbol>]
    RECORDED_METHODS = %i[
      get post put patch delete match root
      resources resource
      namespace scope constraints defaults
      mount concern concerns
    ].freeze

    # All supported HTTP verbs.
    #
    # @return [Array<Symbol>]
    VERBS_ALL = %i[get post put patch delete head options].freeze

    # Default result for no traversal match.
    #
    # @return [Array]
    NO_TRAVERSAL_RESULT = [nil, false].freeze

    # Built-in validators for constraints.
    #
    # @return [Hash{Symbol => Symbol}]
    BUILTIN_VALIDATORS = {
      int: :validate_int_constraint,
      uuid: :validate_uuid_constraint,
      email: :validate_email_constraint,
      slug: :validate_slug_constraint,
      alpha: :validate_alpha_constraint,
      alphanumeric: :validate_alphanumeric_constraint
    }.freeze

    # Build a descriptor Hash for a raw segment string.
    #
    # @param raw [String, #to_s] The raw segment string.
    # @return [Hash] A descriptor hash with frozen values.
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
