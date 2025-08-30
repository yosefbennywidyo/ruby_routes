# frozen_string_literal: true
module RubyRoutes
  class Route
    # ParamSupport: small helpers for param merging + cache key
    module ParamSupport
      private

      # (extracted from Route) keep original semantics
      def build_merged_params(params)
        return @defaults if params.nil? || params.empty?
        work = Thread.current[:ruby_routes_merge_hash] ||= {}
        work.clear
        @defaults.each { |k, v| work[k] = v } unless @defaults.empty?
        params.each do |k, v|
          next if v.nil?
          work[k.is_a?(String) ? k : k.to_s] = v
        end
        work
      end

      # Slim wrapper: build (already frozen) key and update 2‑slot cache.
      def build_param_cache_key(merged)
        key = cache_key_for_params(@required_params, merged) # returns frozen
        hv  = key.hash
        if (slot = @param_key_slots[0])[0] == hv && slot[1] == key
          return slot[1]
        elsif (slot = @param_key_slots[1])[0] == hv && slot[1] == key
          return slot[1]
        end
        store_param_key_slot(hv, key)
      end

      def store_param_key_slot(hash_val, key)
        if @param_key_slots[0][0].nil?
          @param_key_slots[0] = [hash_val, key]
        elsif @param_key_slots[1][0].nil?
          @param_key_slots[1] = [hash_val, key]
        else
          @param_key_slots[0] = @param_key_slots[1]
          @param_key_slots[1] = [hash_val, key]
        end
        key
      end
    end
  end
end
