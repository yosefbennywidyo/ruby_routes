require_relative 'segment'
require_relative 'utility/path_utility'

module RubyRoutes
  # RadixTree provides an optimized tree structure for fast route matching.
  # Supports static segments, dynamic parameters (:param), and wildcards (*splat).
  # Features longest prefix matching and improved LRU caching for performance.
  class RadixTree
    include RubyRoutes::Utility::PathUtility

    class << self
      # Allow RadixTree.new(path, options...) to act as a convenience factory
      def new(*args, &block)
        if args.any?
          RubyRoutes::Route.new(*args, &block)
        else
          super()
        end
      end
    end

    def initialize
      @root = Node.new
      @split_cache = {}
      @split_cache_order = []
      @split_cache_max = 2048
      @empty_segments = [].freeze
    end

    # Add a route to the radix tree with specified path, HTTP methods, and handler.
    # Returns the handler for method chaining.
    def add(path, methods, handler)
      # Normalize path
      normalized_path = normalize_path(path)

      # Insert into the tree
      insert_route(normalized_path, methods, handler)

      # Return handler for chaining
      handler
    end

    # Insert a route into the tree structure, creating nodes as needed.
    # Supports static segments, dynamic parameters (:param), and wildcards (*splat).
    def insert_route(path_str, methods, handler)
      # Skip empty paths
      return handler if path_str.nil? || path_str.empty?

      path_parts = split_path(path_str)
      current_node = @root

      # Add path segments to tree
      path_parts.each_with_index do |segment, i|
        if segment.start_with?(':')
          # Dynamic segment (e.g., :id)
          param_name = segment[1..-1]

          # Create dynamic child if needed
          unless current_node.dynamic_child
            current_node.dynamic_child = Node.new
            current_node.dynamic_child.param_name = param_name
          end

          current_node = current_node.dynamic_child
        elsif segment.start_with?('*')
          # Wildcard segment (e.g., *path)
          param_name = segment[1..-1]

          # Create wildcard child if needed
          unless current_node.wildcard_child
            current_node.wildcard_child = Node.new
            current_node.wildcard_child.param_name = param_name
          end

          current_node = current_node.wildcard_child
          break  # Wildcard consumes the rest of the path
        else
          # Static segment - freeze key for memory efficiency and performance
          segment_key = segment.freeze
          unless current_node.static_children[segment_key]
            current_node.static_children[segment_key] = Node.new
          end

          current_node = current_node.static_children[segment_key]
        end
      end

      # Mark node as endpoint and add handler for methods
      current_node.is_endpoint = true
      Array(methods).each do |method|
        method_str = method.to_s.upcase
        current_node.handlers[method_str] = handler
      end

      handler
    end

    # Find a matching route in the radix tree with longest prefix match support.
    # Tracks the deepest endpoint node during traversal so partial matches return
    # the longest valid prefix, increasing matching flexibility and correctness
    # for overlapping/static/dynamic/wildcard routes.
    def find(path, method, params_out = {})
      # Handle empty path as root
      path_str = path.to_s
      method_str = method.to_s.upcase

      # Special case for root path
      if path_str.empty? || path_str == '/'
        if @root.is_endpoint && @root.handlers[method_str]
          return [@root.handlers[method_str], params_out || {}]
        else
          return [nil, params_out || {}]
        end
      end

      # Split path into segments
      segments = split_path_cached(path_str)
      return [nil, params_out || {}] if segments.empty?

      params = params_out || {}
      
      # Track the longest prefix match (deepest endpoint found during traversal)
      # Only consider nodes that actually match some part of the path
      longest_match_node = nil
      longest_match_params = nil

      # Traverse the tree to find matching route
      current_node = @root
      segments.each_with_index do |segment, i|
        next_node, should_break = current_node.traverse_for(segment, i, segments, params)

        # No match found for this segment
        unless next_node
          # Return longest prefix match if we found any valid endpoint during traversal
          if longest_match_node
            handler = longest_match_node.handlers[method_str]
            if handler.respond_to?(:constraints)
              constraints = handler.constraints
              if constraints && !constraints.empty?
                return check_constraints(handler, longest_match_params) ? [handler, longest_match_params] : [nil, params]
              end
            end
            return [handler, longest_match_params]
          end
          return [nil, params]
        end

        current_node = next_node
        
        # Check if current node is a valid endpoint after successful traversal
        if current_node.is_endpoint && current_node.handlers[method_str]
          # Store this as our current best match
          longest_match_node = current_node
          longest_match_params = params.dup
        end
        
        break if should_break  # For wildcard paths
      end

      # Check if final node is an endpoint and has a handler for the method
      if current_node.is_endpoint && current_node.handlers[method_str]
        handler = current_node.handlers[method_str]

        # Handle constraints correctly - only check constraints
        # Don't try to call matches? which test doubles won't have properly stubbed
        if handler.respond_to?(:constraints)
          constraints = handler.constraints
          if constraints && !constraints.empty?
            if check_constraints(handler, params)
              return [handler, params]
            else
              # If constraints fail, try longest prefix match as fallback
              if longest_match_node && longest_match_node != current_node
                fallback_handler = longest_match_node.handlers[method_str]
                return [fallback_handler, longest_match_params] if fallback_handler
              end
              return [nil, params]
            end
          end
        end

        return [handler, params]
      end

      # If we reach here, final node isn't an endpoint - return longest prefix match
      if longest_match_node
        handler = longest_match_node.handlers[method_str]
        if handler.respond_to?(:constraints)
          constraints = handler.constraints
          if constraints && !constraints.empty?
            return check_constraints(handler, longest_match_params) ? [handler, longest_match_params] : [nil, params]
          end
        end
        return [handler, longest_match_params]
      end

      [nil, params]
    end

    private

    # Improved LRU Path Segment Cache: Accessed keys are moved to the end of the 
    # order array to ensure proper LRU eviction behavior
    def split_path_cached(path)
      return @empty_segments if path == '/'

      # Check if path is in cache
      if @split_cache.key?(path)
        # Move accessed key to end for proper LRU behavior
        @split_cache_order.delete(path)
        @split_cache_order << path
        return @split_cache[path]
      end

      # Split path and add to cache
      segments = split_path(path)

      # Manage cache size - evict oldest entries when limit reached
      if @split_cache.size >= @split_cache_max
        old_key = @split_cache_order.shift
        @split_cache.delete(old_key)
      end

      @split_cache[path] = segments
      @split_cache_order << path

      segments
    end

    # Validates route constraints against extracted parameters.
    # Returns true if all constraints pass, false otherwise.
    def check_constraints(handler, params)
      return true unless handler.respond_to?(:constraints)

      constraints = handler.constraints
      return true unless constraints && !constraints.empty?

      # Check each constraint
      constraints.each do |param, constraint|
        param_key = param.to_s
        value = params[param_key]
        next unless value

        case constraint
        when Regexp
          return false unless constraint.match?(value.to_s)
        when :int
          return false unless value.to_s.match?(/\A\d+\z/)
        when :uuid
          return false unless value.to_s.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
        when Hash
          if constraint[:range].is_a?(Range)
            value_num = value.to_i
            return false unless constraint[:range].include?(value_num)
          end
        end
      end

      true
    end
  end
end
