require_relative 'segment'

module RubyRoutes
  class Node
    attr_accessor :static_children, :dynamic_child, :wildcard_child,
                  :handlers, :param_name, :is_endpoint

    def initialize
      @static_children = {}
      @dynamic_child = nil
      @wildcard_child = nil
      @handlers = {}
      @param_name = nil
      @is_endpoint = false
    end

    # Fast traversal: minimal allocations, streamlined branching
    # Returns [next_node_or_nil, should_break_bool] or [nil, false] if no match.
    def traverse_for(segment, index, segments, params)
      # Static match: O(1) hash lookup
      child = @static_children[segment]
      return [child, false] if child

      # Dynamic match: single segment capture
      if (dyn = @dynamic_child)
        params[dyn.param_name] = segment if params
        return [dyn, false]
      end

      # Wildcard match: consume remainder (last resort)
      if (wild = @wildcard_child)
        if params
          # Build remainder path without intermediate array allocation
          remainder = segments[index..-1]
          params[wild.param_name] = remainder.size == 1 ? remainder[0] : remainder.join('/')
        end
        return [wild, true]
      end

      # No match
      [nil, false]
    end

    # Pre-cache param names as strings to avoid repeated .to_s calls
    def param_name
      @param_name_str ||= @param_name&.to_s
    end

    def param_name=(name)
      @param_name = name
      @param_name_str = nil  # invalidate cache
    end

    # Normalize method once and cache string keys
    def add_handler(method, handler)
      method_key = method.to_s.upcase
      @handlers[method_key] = handler
      @is_endpoint = true
    end

    def get_handler(method)
      @handlers[method]  # assume already normalized upstream
    end
  end
end
