# frozen_string_literal: true

require_relative 'small_lru'

module RubyRoutes
  class Route
    # PathBuilder: generation + segment encoding
    module PathBuilder
      private

      # Generate the path string from merged parameters.
      #
      # @param merged [Hash] the merged parameters
      # @return [String] the generated path
      def generate_path_string(merged)
        return RubyRoutes::Constant::ROOT_PATH if @compiled_segments.empty?

        buffer = String.new(capacity: estimate_length)
        buffer << '/'
        last_index = @compiled_segments.length - 1
        @compiled_segments.each_with_index do |segment, index|
          append_segment(buffer, segment, merged, index, last_index)
        end
        buffer
      end

      # Append a segment to the buffer.
      #
      # @param buffer [String] the buffer to append to
      # @param segment [RubyRoutes::Segments::BaseSegment] the segment to append
      # @param merged [Hash] the merged parameters
      # @param index [Integer] the current index
      # @param last_index [Integer] the last index
      def append_segment(buffer, segment, merged, index, last_index)
        case segment[:type]
        when :static
          buffer << segment[:value]
        when :param
          buffer << encode_segment_fast(merged.fetch(segment[:name]).to_s)
        when :splat
          buffer << format_splat_value(merged.fetch(segment[:name], ''))
        end
        buffer << '/' unless index == last_index
      end

      # Estimate the length of the path.
      #
      # @return [Integer] the estimated length
      def estimate_length
        # Rough heuristic (static sizes + average dynamic)
        base = 1
        @compiled_segments.each do |segment|
          base += case segment
                  when RubyRoutes::Segments::StaticSegment then segment.literal_text.length + 1
                  else 20
                  end
        end
        base
      end

      # Format a splat value.
      #
      # @param value [Object] the value to format
      # @return [String] the formatted value
      def format_splat_value(value)
        case value
        when Array  then value.map { |part| encode_segment_fast(part.to_s) }.join('/')
        when String then value.split('/').map { |part| encode_segment_fast(part) }.join('/')
        else encode_segment_fast(value.to_s)
        end
      end

      # Encode a segment fast.
      #
      # @param string [String] the string to encode
      # @return [String] the encoded string
      def encode_segment_fast(string)
        return string if RubyRoutes::Constant::UNRESERVED_RE.match?(string)

        @encoding_cache ||= RubyRoutes::Route::SmallLru.new(256)
        cached = @encoding_cache.get(string)
        return cached if cached

        encoded = URI.encode_www_form_component(string).gsub('+', '%20')
        @encoding_cache.set(string, encoded)
      end
    end
  end
end
