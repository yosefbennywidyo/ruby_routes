# frozen_string_literal: true

module RubyRoutes
  module Utility
    # PathUtility
    #
    # Low‑allocation helpers for normalizing and manipulating URL path
    # strings used during route definition, recognition, and generation.
    #
    # @note Design goals:
    #   - Idempotent normalization: ensure a single leading slash and trim one
    #     trailing slash (except for root).
    #   - Internal duplicate slashes are tolerated by `normalize_path`; `split_path`
    #     collapses empty segments; `join_path_parts` never produces duplicate
    #     separators
    #
    # @note Thread safety: stateless (all methods pure).
    #
    # @api internal
    module PathUtility
      # Normalize a raw path string.
      #
      # Rules:
      # - Ensures a leading slash.
      # - Removes a trailing slash (except when the path is exactly "/").
      #
      # @param raw_path [String, #to_s]
      # @return [String] normalized path (may be the same object if unchanged)
      #
      # @example
      #   normalize_path('users/')   # => "/users"
      #   normalize_path('/users')   # => "/users"
      #   normalize_path('/')        # => "/"
      def normalize_path(raw_path)
        return '/' if raw_path.nil? || raw_path.empty?

        path = raw_path.start_with?('/') ? raw_path : "/#{raw_path}"
        path = path.chomp('/') unless path == '/'
        path
      end

      # Normalize HTTP method to uppercase String (fast path).
      #
      # @param method [String, Symbol]
      # @return [String]
      def normalize_method(method)
        method.to_s.upcase
      end

      # Split a path into its component segments (excluding leading/trailing slash
      # and any query string). Returns an empty Array for root.
      #
      # @param raw_path [String]
      # @return [Array<String>] segments without empty elements
      #
      # @example
      #   split_path('/users/123?x=1') # => ["users", "123"]
      #   split_path('/')              # => []
      def split_path(raw_path)
        return [] if raw_path == '/' || raw_path.empty?

        # Strip query strings and fragments
        path = raw_path.split(/[?#]/).first

        # Optimized trimming: avoid string allocations when possible
        start_idx = path.start_with?('/') ? 1 : 0
        end_idx = path.end_with?('/') ? -2 : -1

        if start_idx == 0 && end_idx == -1
          path.split('/').reject(&:empty?)
        else
          path[start_idx..end_idx].split('/').reject(&:empty?)
        end
      end

      # Join path parts into a normalized absolute path.
      #
      # Allocation minimization:
      # - Precomputes total size to preallocate destination String.
      # - Appends with manual slash insertion.
      #
      # @param path_parts [Array<String>]
      # @return [String] absolute path beginning with '/'
      #
      # @example
      #   join_path_parts(%w[users 123]) # => "/users/123"
      def join_path_parts(path_parts)
        estimated_path_size = path_parts.sum { |path_part| path_part.length + 1 } # +1 per slash
        path_buffer = String.new(capacity: estimated_path_size)
        path_buffer << '/'
        last_part_index = path_parts.size - 1
        path_parts.each_with_index do |path_part, part_index|
          path_buffer << path_part
          path_buffer << '/' unless part_index == last_part_index
        end
        path_buffer
      end
    end
  end
end
