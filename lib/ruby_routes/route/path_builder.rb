# frozen_string_literal: true
module RubyRoutes
  class Route
    # PathBuilder: generation + segment encoding
    module PathBuilder
      private

      def generate_path_string(merged)
        return RubyRoutes::Constant::ROOT_PATH if @compiled_segments.empty?
        buf = String.new(capacity: estimate_length)
        buf << '/'
        last = @compiled_segments.length - 1
        @compiled_segments.each_with_index do |seg, idx|
          case seg[:type]
          when :static
            buf << seg[:value]
          when :param
            buf << encode_segment_fast(merged.fetch(seg[:name]).to_s)
          when :splat
            buf << format_splat_value(merged.fetch(seg[:name], ''))
          end
          buf << '/' unless idx == last
        end
        buf
      end

      def estimate_length
        # Rough heuristic (static sizes + average dynamic)
        base = 1
        @compiled_segments.each do |s|
            base += case s[:type]
                    when :static then s[:value].length + 1
                    else 20
                    end
        end
        base
      end

      def format_splat_value(v)
        case v
        when Array  then v.map { |p| encode_segment_fast(p.to_s) }.join('/')
        when String then v.split('/').map { |p| encode_segment_fast(p) }.join('/')
        else encode_segment_fast(v.to_s)
        end
      end

      def encode_segment_fast(str)
        return str if RubyRoutes::Constant::UNRESERVED_RE.match?(str)
        @encoding_cache ||= {}
        # Use gsub instead of tr for proper replacement of + with %20
        @encoding_cache[str] ||= URI.encode_www_form_component(str).gsub('+', '%20')
      end
    end
  end
end
