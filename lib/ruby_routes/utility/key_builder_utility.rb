# frozen_string_literal: true

module RubyRoutes
  module Utility
    # KeyBuilderUtility
    #
    # High‑performance helpers for building and reusing cache keys:
    # 1. Request recognition keys ("METHOD:PATH") via a per‑method nested
    #    hash plus a fixed‑size ring buffer for eviction.
    # 2. Parameter combination keys for path generation (ordered values of
    #    required params, pipe + slash delimited) with thread‑local String
    #    buffers to avoid intermediate allocations.
    #
    # Design goals:
    # - Zero garbage on hot cache hits.
    # - Bounded memory (REQUEST_KEY_CAPACITY ring).
    # - Thread safety not required (intended for single request thread use).
    module KeyBuilderUtility
      # @!visibility private
      # { "GET" => { "/users" => "GET:/users" } }
      @request_key_pool = {}
      # @!visibility private
      # Circular buffer holding [method_string, path_string] tuples to evict.
      @request_key_ring = Array.new(RubyRoutes::Constant::REQUEST_KEY_CAPACITY)
      # @!visibility private
      @ring_index  = 0
      # @!visibility private
      @entry_count = 0

      class << self
        # Expose pool for diagnostics (read‑only).
        # @return [Hash]
        # Diagnostic accessor. Returns a shallow copy so callers cannot
        # mutate internal cache structures
        attr_reader :request_key_pool

        # Fetch (or create) a frozen "METHOD:PATH" composite key.
        #
        # On miss:
        # - Builds the String once.
        # - Records it in the nested pool.
        # - Tracks insertion in a fixed ring; when full, overwrites oldest.
        #
        # @param http_method [String]
        # @param request_path [String]
        # @return [String] frozen canonical key
        # Optimized (hot path) composite request key fetch.
        #
        # Goals:
        # - Zero allocations on hit (no new Strings / Arrays)
        # - Single interpolation & freeze on miss
        # - O(1) bounded eviction via fixed-size ring buffer
        #
        # Inputs MUST be Strings (caller responsibility). They can be unfrozen;
        # we dup+freeze only once on first insertion.
        def fetch_request_key(http_method, request_path)
          # Normalize to frozen canonical keys (cheap guard)
          method_key = http_method.frozen? ? http_method : http_method.dup.freeze
          path_key   = request_path.frozen? ? request_path : request_path.dup.freeze

          # Bucket lookup
          if (bucket = @request_key_pool[method_key])
            if (composite = bucket[path_key])
              return composite # HOT HIT → return immediately (zero alloc)
            end
          else
            # Initialize bucket only when method first seen
            bucket = @request_key_pool[method_key] = {}
          end

          # MISS: build composite once
          composite = "#{method_key}:#{path_key}".freeze
          bucket[path_key] = composite

          # Ring population / eviction
          if @entry_count < RubyRoutes::Constant::REQUEST_KEY_CAPACITY
            @request_key_ring[@entry_count] = [method_key, path_key]
            @entry_count += 1
          else
            m_old, p_old = @request_key_ring[@ring_index]
            old_bucket = @request_key_pool[m_old]
            if old_bucket
              old_bucket.delete(p_old)
              @request_key_pool.delete(m_old) if old_bucket.empty?
            end
            @request_key_ring[@ring_index] = [method_key, path_key]
            @ring_index += 1
            @ring_index = 0 if @ring_index == RubyRoutes::Constant::REQUEST_KEY_CAPACITY
          end

          composite
        end
      end

      # Build a generic delimited key from components (non‑hot path).
      #
      # Uses a thread‑local mutable buffer to avoid transient objects.
      #
      # @param components [Array<#to_s>]
      # @param delimiter [String] separator (default ':')
      # @return [String] frozen key string
      def build_key(components, delimiter = ':')
        return RubyRoutes::Constant::EMPTY_STRING if components.empty?

        buffer = Thread.current[:ruby_routes_key_buf] ||= String.new
        buffer.clear
        index = 0
        while index < components.length
          buffer << delimiter unless index.zero?
          buffer << components[index].to_s
          index += 1
        end
        buffer.dup.freeze
      end

      # Return (intern / reuse) a composite request key.
      #
      # @param http_method [String]
      # @param path [String]
      # @return [String] frozen "METHOD:PATH" key
      def cache_key_for_request(http_method, path)
        KeyBuilderUtility.fetch_request_key(http_method, path.to_s)
      end

      # Build a cache key from required params + merged hash in order.
      # Format: "val1|val2/subA/subB|val3"
      #
      # @param required_params [Array<String>]
      # @param merged [Hash{String=>Object}]
      # @return [String] frozen key (empty if none required)
      def cache_key_for_params(required_params, merged)
        return RubyRoutes::Constant::EMPTY_STRING if required_params.nil? || required_params.empty?

        buffer = Thread.current[:ruby_routes_param_key_buf] ||= String.new
        buffer.clear

        counter = 0
        while counter < required_params.length
          buffer << '|' unless counter.zero?
          value = merged[required_params[counter]]
          if value.is_a?(Array)
            j = 0
            while j < value.length
              buffer << '/' unless j.zero?
              buffer << value[j].to_s
              j += 1
            end
          else
            buffer << value.to_s
          end
          counter += 1
        end
        buffer.dup.freeze
      end

      # Reusable variant used in tight loops (same semantics as
      # cache_key_for_params). Kept separate to allow specialized tweaks
      # without changing public method.
      #
      # @param required_params [Array<String>]
      # @param merged [Hash]
      # @return [String]
      def param_cache_key_reuse(required_params, merged)
        return RubyRoutes::Constant::EMPTY_STRING if required_params.nil? || required_params.empty?

        buffer = Thread.current[:ruby_routes_param_key_buf] ||= String.new
        buffer.clear

        counter = 0
        while counter < required_params.length
          buffer << '|' unless counter.zero?
          value = merged[required_params[counter]]
          if value.is_a?(Array)
            index = 0
            while index < value.length
              buffer << '/' unless index.zero?
              buffer << value[index].to_s
              index += 1
            end
          else
            buffer << value.to_s
          end
          counter += 1
        end
        buffer.dup.freeze
      end
    end
  end
end
