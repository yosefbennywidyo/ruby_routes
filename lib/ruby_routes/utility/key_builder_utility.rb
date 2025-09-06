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
    # - Thread-safe for concurrent access across multiple threads.
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
      # @!visibility private
      @mutex = Mutex.new

      class << self
        # Clear all cached request keys.
        #
        # @return [void]
        def clear!
          @mutex.synchronize do
            @request_key_pool.clear
            @request_key_ring.fill(nil)
            @entry_count = 0
            @ring_index = 0
          end
        end

        # Fetch (or create) a frozen "METHOD:PATH" composite key.
        #
        # On miss:
        # - Builds the String once.
        # - Records it in the nested pool.
        # - Tracks insertion in a fixed ring; when full, overwrites oldest.
        #
        # @param request_path [String] The request path (e.g., "/users").
        # @return [String] A frozen canonical key.
        def fetch_request_key(http_method, request_path)
          @mutex.synchronize do
            method_key = http_method.freeze
            path_key = request_path.to_s.freeze
            bucket = @request_key_pool[method_key] ||= {}
            bucket[path_key] || create_and_cache_key(bucket, method_key, path_key)
          end
        end

        def create_and_cache_key(bucket, method_key, path_key)
          composite = "#{method_key}:#{path_key}".freeze
          bucket[path_key] = composite
          handle_ring_buffer(method_key, path_key)
          composite
        end

        # Handle the ring buffer for eviction.
        #
        # @param method_key [String] The HTTP method key.
        # @param path_key [String] The path key.
        # @return [void]
        def handle_ring_buffer(method_key, path_key)
          evict_old_entry if @entry_count >= RubyRoutes::Constant::REQUEST_KEY_CAPACITY
          add_to_ring_buffer(method_key, path_key)
        end

        # Add a key to the ring buffer.
        #
        # @param method_key [String] The HTTP method key.
        # @param path_key [String] The path key.
        # @return [void]
        def add_to_ring_buffer(method_key, path_key)
          @request_key_ring[@ring_index] = [method_key, path_key]
          @ring_index = (@ring_index + 1) % RubyRoutes::Constant::REQUEST_KEY_CAPACITY
          @entry_count += 1 if @entry_count < RubyRoutes::Constant::REQUEST_KEY_CAPACITY
        end

        # Evict the oldest entry from the ring buffer.
        #
        # @return [void]
        def evict_old_entry
          old_method, old_path = @request_key_ring[@ring_index]
          old_method_bucket = @request_key_pool[old_method]
          return unless old_method_bucket

          old_method_bucket.delete(old_path)
          @request_key_pool.delete(old_method) if old_method_bucket.empty?
        end
      end

      # Build a generic delimited key from components (non‑hot path).
      #
      # Simple join; acceptable for non‑hot paths.
      #
      # @param components [Array<#to_s>] The components to join into a key.
      # @param delimiter [String] The separator (default is ':').
      # @return [String] A frozen key string.
      def build_key(components, delimiter = ':')
        return RubyRoutes::Constant::EMPTY_STRING if components.empty?

        components.map(&:to_s).join(delimiter).freeze
      end

      # Return (intern/reuse) a composite request key.
      #
      # @param http_method [String] The HTTP method.
      # @param path [String] The request path.
      # @return [String] A frozen "METHOD:PATH" key.
      def cache_key_for_request(http_method, path)
        KeyBuilderUtility.fetch_request_key(http_method, path.to_s)
      end

      # Build a cache key from required params and a merged hash in order.
      #
      # Format: "val1|val2/subA/subB|val3".
      #
      # @param required_params [Array<String>] The required parameter keys.
      # @param merged [Hash{String=>Object}] The merged parameters.
      # @return [String] A frozen key (empty if none required).
      def cache_key_for_params(required_params, merged)
        return RubyRoutes::Constant::EMPTY_STRING if required_params.nil? || required_params.empty?

        buffer = Thread.current[:ruby_routes_param_key_buf] ||= String.new
        buffer.clear
        build_param_key_buffer(required_params, merged, buffer)
        buffer.dup.freeze
      end

      # Build the parameter key buffer.
      #
      # @param required_params [Array<String>] The required parameter keys.
      # @param merged [Hash] The merged parameters.
      # @param buffer [String] The buffer to build the key into.
      # @return [void]
      def build_param_key_buffer(required_params, merged, buffer)
        first = true
        required_params.each do |param|
          value = format_param_value(merged[param])
          if first
            buffer << value
            first = false
          else
            buffer << '|' << value
          end
        end
      end

      # Format a parameter value for inclusion in the key.
      #
      # @param param_value [Object] The parameter value.
      # @return [String] The formatted parameter value.
      def format_param_value(param_value)
        if param_value.is_a?(Array)
          param_value.join('/')
        else
          param_value.to_s
        end
      end
    end
  end
end
