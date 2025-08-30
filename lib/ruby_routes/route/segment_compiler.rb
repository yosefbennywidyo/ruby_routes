# frozen_string_literal: true
module RubyRoutes
  class Route
    # SegmentCompiler: path analysis + extraction
    module SegmentCompiler
      private

      def compile_segments
        @compiled_segments =
          if @path == RubyRoutes::Constant::ROOT_PATH
            RubyRoutes::Constant::EMPTY_ARRAY
          else
            @path.split('/').reject(&:empty?)
                 .map { |seg| RubyRoutes::Constant.segment_descriptor(seg) }
                 .freeze
          end
      end

      def compile_required_params
        dyn = @compiled_segments.filter_map { |s| s[:name] if s[:type] != :static }
        @param_names         = dyn.freeze
        @required_params     = dyn.reject { |n| @defaults.key?(n) }.freeze
        @required_params_set = @required_params.to_set.freeze
      end

      def check_static_path
        return unless @compiled_segments.all? { |s| s[:type] == :static }
        @static_path = generate_static_path
      end

      def generate_static_path
        return RubyRoutes::Constant::ROOT_PATH if @compiled_segments.empty?
        "/#{@compiled_segments.map { |s| s[:value] }.join('/')}"
      end

      def extract_path_params_fast(request_path)
        return RubyRoutes::Constant::EMPTY_HASH if @compiled_segments.empty? &&
                                                   request_path == RubyRoutes::Constant::ROOT_PATH
        return nil if @compiled_segments.empty?
        parts = split_path(request_path)
        with_splat = @compiled_segments.any? { |s| s[:type] == :splat }
        return nil if (!with_splat && parts.size != @compiled_segments.size) ||
                      (with_splat && parts.size < (@compiled_segments.size - 1))
        extract_params_from_parts(parts)
      end

      def extract_params_from_parts(parts)
        out = {}
        @compiled_segments.each_with_index do |seg, i|
          case seg[:type]
          when :static
            return nil unless seg[:value] == parts[i]
          when :param
            out[seg[:name]] = parts[i]
          when :splat
            out[seg[:name]] = parts[i..].join('/')
            break
          end
        end
        out
      end
    end
  end
end
