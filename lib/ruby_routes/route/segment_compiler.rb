# frozen_string_literal: true

module RubyRoutes
  class Route
    # SegmentCompiler: path analysis + extraction
    #
    # This module provides methods for analyzing and extracting segments from
    # a route path. It includes utilities for compiling path segments, required
    # parameters, and static paths, as well as extracting parameters from a
    # request path.
    #
    # @module RubyRoutes::Route::SegmentCompiler
    module SegmentCompiler
      private

      # Compile the segments from the path.
      #
      # This method splits the path into segments, analyzes each segment, and
      # compiles metadata for static and dynamic segments.
      #
      # @return [void]
      def compile_segments
        @compiled_segments =
          if @path == RubyRoutes::Constant::ROOT_PATH
            RubyRoutes::Constant::EMPTY_ARRAY
          else
            @path.split('/').reject(&:empty?)
                 .map { |segment| RubyRoutes::Constant.segment_descriptor(segment) }
                 .freeze
          end
      end

      # Compile the required parameters.
      #
      # This method identifies dynamic parameters in the path and determines
      # which parameters are required based on the defaults provided.
      #
      # @return [void]
      def compile_required_params
        dynamic_param_names   = @compiled_segments.filter_map { |segment| segment[:name] if segment[:type] != :static }
        @param_names          = dynamic_param_names.freeze
        @required_params      = if @defaults.empty?
                                  dynamic_param_names.freeze
                                else
                                  dynamic_param_names.reject do |name|
                                    @defaults.key?(name) || @defaults.key?(name.to_sym)
                                  end.freeze
                                end
        @required_params_set  = @required_params.to_set.freeze
      end

      # Check if the path is static.
      #
      # This method determines if the path contains only static segments. If so,
      # it generates the static path.
      #
      # @return [void]
      def check_static_path
        return unless @compiled_segments.all? { |segment| segment[:type] == :static }

        @static_path = generate_static_path
      end

      # Generate the static path.
      #
      # This method constructs the static path from the compiled segments.
      #
      # @return [String] The generated static path.
      def generate_static_path
        return RubyRoutes::Constant::ROOT_PATH if @compiled_segments.empty?

        "/#{@compiled_segments.map { |segment| segment[:value] }.join('/')}"
      end

      # Extract path parameters fast.
      #
      # This method extracts parameters from a request path based on the compiled
      # segments. It performs validation and handles dynamic, static, and splat
      # segments.
      #
      # @param request_path [String] The request path.
      # @return [Hash, nil] The extracted parameters, or `nil` if extraction fails.
      def extract_path_params_fast(request_path)
        return RubyRoutes::Constant::EMPTY_HASH if root_path_and_empty_segments?(request_path)

        return nil if @compiled_segments.empty?

        path_parts = split_path(request_path)
        return nil unless valid_parts_count?(path_parts)

        extract_params_from_parts(path_parts)
      end

      # Check if it's a root path with empty segments.
      #
      # This method checks if the request path is the root path and the compiled
      # segments are empty.
      #
      # @param request_path [String] The request path.
      # @return [Boolean] `true` if the path is the root path with empty segments, `false` otherwise.
      def root_path_and_empty_segments?(request_path)
        @compiled_segments.empty? && request_path == RubyRoutes::Constant::ROOT_PATH
      end

      # Validate the parts count.
      #
      # This method checks if the number of parts in the request path matches
      # the expected number of segments, accounting for splat segments.
      #
      # @param path_parts [Array<String>] The path parts.
      # @return [Boolean] `true` if the parts count is valid, `false` otherwise.
      def valid_parts_count?(path_parts)
        has_splat = @compiled_segments.any? { |segment| segment[:type] == :splat }
        (!has_splat && path_parts.size == @compiled_segments.size) ||
          (has_splat && path_parts.size >= (@compiled_segments.size - 1))
      end

      # Extract parameters from parts.
      #
      # This method processes each segment and extracts parameters from the
      # corresponding parts of the request path.
      #
      # @param path_parts [Array<String>] The path parts.
      # @return [Hash, nil] The extracted parameters, or `nil` if extraction fails.
      def extract_params_from_parts(path_parts)
        params_hash = {}
        @compiled_segments.each_with_index do |segment, index|
          result = process_segment(segment, index, path_parts, params_hash)
          return nil if result == false
          break if result == :break
        end
        params_hash
      end

      # Process a segment.
      #
      # This method processes a single segment, extracting parameters or
      # validating static segments.
      #
      # @param segment [Hash] The segment metadata.
      # @param index [Integer] The index of the segment.
      # @param path_parts [Array<String>] The path parts.
      # @param params_hash [Hash] The parameters hash.
      # @return [Boolean, Symbol] `true` if processed successfully,
      # `false` if validation fails, `:break` for splat segments.
      def process_segment(segment, index, path_parts, params_hash)
        case segment[:type]
        when :static
          segment[:value] == path_parts[index]
        when :param
          params_hash[segment[:name]] = path_parts[index]
          true
        when :splat
          params_hash[segment[:name]] = path_parts[index..].join('/')
          :break
        end
      end

      # Expose for testing / external callers that need fast path extraction.
      public :extract_path_params_fast
    end
  end
end
