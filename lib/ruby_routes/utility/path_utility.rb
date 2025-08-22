module RubyRoutes
  module Utility
    module PathUtility
      ROOT_PATH = '/'.freeze

      def normalize_path(path)
        path = path.to_s
        # Add leading slash if missing
        path = '/' + path unless path.start_with?('/')
        # Remove trailing slash if present (unless root)
        path = path[0..-2] if path.length > 1 && path.end_with?('/')
        path
      end

      def split_path(path)
        # Remove query string before splitting
        path = path.split('?', 2).first
        path = path[1..-1] if path.start_with?('/')
        path = path[0...-1] if path.end_with?('/') && path != ROOT_PATH
        path.empty? ? [] : path.split('/')
      end

      def join_path_parts(parts)
        # Pre-calculate the size to avoid buffer resizing
        size = parts.sum { |p| p.length + 1 } # +1 for slash

        # Use string buffer for better performance
        result = String.new(capacity: size)
        result << '/'

        # Join with explicit concatenation rather than array join
        last_idx = parts.size - 1
        parts.each_with_index do |part, i|
          result << part
          result << '/' unless i == last_idx
        end

        result
      end
    end
  end
end
