# frozen_string_literal: true

module RubyRoutes
  module Utility
    # PathUtility
    #
    # Low‑allocation helpers for normalizing and manipulating URL path
    # strings used during route definition, recognition, and generation.
    #
    # Design goals:
    # - Idempotent normalization (no double slashes, trailing slash trimmed
    #   except for root).
    # - Avoid intermediate Array/String allocations where possible.
    # - Provide fast splitting suitable for hot routing paths.
    #
    # Thread safety: stateless (all methods pure).
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
        normalized = raw_path.to_s
        normalized = "/#{normalized}" unless normalized.start_with?('/')
        normalized = normalized[0..-2] if normalized.length > 1 && normalized.end_with?('/')
        normalized
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
        path_no_query = raw_path.to_s.split('?', 2).first
        return [] if path_no_query.empty?

        path_no_query.split('/').reject(&:empty?)
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
        estimated_size = path_parts.sum { |part| part.length + 1 } # +1 per slash
        buffer = String.new(capacity: estimated_size)
        buffer << '/'
        last_index = path_parts.size - 1
        path_parts.each_with_index do |part, index|
          buffer << part
          buffer << '/' unless index == last_index
        end
        buffer
      end
    end
  end
end
