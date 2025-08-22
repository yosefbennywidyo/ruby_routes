module RubyRoutes
  module Utility
    module KeyBuilderUtility
      # ------------------------------------------------------------------
      # Fast reusable key storage for "METHOD:PATH" strings.
      # O(1) insert + O(1) eviction using a fixed-size ring buffer.
      # Only allocates a new String on the *first* time a (method,path) pair appears.
      # ------------------------------------------------------------------
      REQUEST_KEY_CAPACITY = 4096

      @pool      = {}                        # { method_string => { path_string => frozen_key_string } }
      @ring      = Array.new(REQUEST_KEY_CAPACITY) # ring entries: [method_string, path_string]
      @ring_pos  = 0
      @entry_cnt = 0

      class << self
        attr_reader :pool
        def fetch_request_key(method, path)
          # Method & path must be strings already (callers ensure)
          if (paths = @pool[method])
            if (key = paths[path])
              return key
            end
          end

            # MISS: build & freeze once
          key = "#{method}:#{path}".freeze
          if paths
            paths[path] = key
          else
            @pool[method] = { path => key }
          end

          # Evict if ring full (overwrite oldest slot)
          if @entry_cnt < REQUEST_KEY_CAPACITY
            @ring[@entry_cnt] = [method, path]
            @entry_cnt += 1
          else
            ev_m, ev_p = @ring[@ring_pos]
            bucket = @pool[ev_m]
            if bucket&.delete(ev_p) && bucket.empty?
              @pool.delete(ev_m)
            end
            @ring[@ring_pos] = [method, path]
            @ring_pos += 1
            @ring_pos = 0 if @ring_pos == REQUEST_KEY_CAPACITY
          end

          key
        end
      end

      # ------------------------------------------------------------------
      # Public helpers mixed into instances
      # ------------------------------------------------------------------

      # Generic key (rarely hot): joins parts with delim; single allocation.
      def build_key(parts, delim = ':')
        return ''.freeze if parts.empty?
        buf = Thread.current[:ruby_routes_key_buf] ||= String.new
        buf.clear
        i = 0
        while i < parts.length
          buf << delim unless i.zero?
          buf << parts[i].to_s
          i += 1
        end
        buf.dup
      end

      # HOT: request cache key (reused frozen interned string)
      def cache_key_for_request(method, path)
        KeyBuilderUtility.fetch_request_key(method, path.to_s)
      end

      # HOT: params key – produces a short-lived String (dup, not re-frozen each time).
      # Callers usually put it into an LRU that duplicates again, so keep it lean.
      def cache_key_for_params(required_params, merged)
        return ''.freeze if required_params.nil? || required_params.empty?
        buf = Thread.current[:ruby_routes_param_key_buf] ||= String.new
        buf.clear
        i = 0
        while i < required_params.length
          buf << '|' unless i.zero?
          v = merged[required_params[i]]
          if v.is_a?(Array)
            j = 0
            while j < v.length
              buf << '/' unless j.zero?
              buf << v[j].to_s
              j += 1
            end
          else
            buf << v.to_s
          end
          i += 1
        end
        buf.dup
      end
    end
  end
end
