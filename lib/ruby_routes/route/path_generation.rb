# frozen_string_literal: true

require_relative 'warning_helpers'

module RubyRoutes
  class Route
    # PathGeneration:
    # Small focused helpers related to building generated paths and emitting
    # route-related warnings (kept separate to reduce parent module size).
    module PathGeneration
      include RubyRoutes::Route::WarningHelpers

      private

      # Generate a path string from supplied params.
      #
      # Rules:
      # - Required params must be present and non‑nil (unless defaulted).
      # - Caches the result keyed on ordered required param values.
      #
      # @param params [Hash] The parameters for path generation (String/Symbol keys).
      # @return [String] The generated path string.
      # @raise [RouteNotFound] If required params are missing or nil.
      def generate_path(params = {})
        return @static_path if static_short_circuit?(params)
        return @static_path || RubyRoutes::Constant::ROOT_PATH if trivial_route?

        validate_required_once(params)
        merged_params = build_merged_params(params)

        build_or_fetch_generated_path(merged_params)
      end

      # Build or fetch a generated path from the cache.
      #
      # This method generates a path string from the merged parameters or fetches
      # it from the cache if it already exists.
      #
      # @param merged_params [Hash] The merged parameters for path generation.
      # @return [String] The generated or cached path string.
      def build_or_fetch_generated_path(merged_params)
        generation_cache_key = build_generation_cache_key(merged_params)
        if (cached_path = @gen_cache.get(generation_cache_key))
          return cached_path
        end

        generated_path = generate_path_string(merged_params)
        @gen_cache.set(generation_cache_key, generated_path)
        generated_path
      end

      # Build a generation cache key for merged params.
      #
      # This method creates a cache key based on the required parameters and
      # their values in the merged parameters.
      #
      # @param merged_params [Hash] The merged parameters for path generation.
      # @return [String] The cache key for the generation cache.
      def build_generation_cache_key(merged_params)
        @required_params.empty? ? RubyRoutes::Constant::EMPTY_STRING : build_param_cache_key(merged_params)
      end

      # Emit deprecation warning for `Proc` constraints once per parameter.
      #
      # This method ensures that a deprecation warning for a `Proc` constraint
      # is only emitted once per parameter. It tracks parameters for which
      # warnings have already been shown.
      #
      # @param param [String, Symbol] The parameter name for which the warning
      #   is being emitted.
      # @return [void]
      def warn_proc_constraint_deprecation(param)
        return if @proc_warnings_shown&.include?(param)

        @proc_warnings_shown ||= Set.new
        @proc_warnings_shown << param
        warn_proc_warning(param)
      end

      # Determine if the route can short-circuit to a static path.
      #
      # This method checks if the route is static and the provided parameters
      # are empty or nil, allowing the static path to be returned directly.
      #
      # @param params [Hash] The parameters for path generation.
      # @return [Boolean] `true` if the route can short-circuit, `false` otherwise.
      def static_short_circuit?(params)
        @static_path && (params.nil? || params.empty?)
      end

      # Determine if the route is trivial.
      #
      # A route is considered trivial if it has no dynamic segments, no required
      # parameters, and no constraints, meaning it can resolve to a static path.
      #
      # @return [Boolean] `true` if the route is trivial, `false` otherwise.
      def trivial_route?
        @compiled_segments.empty? && @required_params.empty? && @constraints.empty?
      end
    end
  end
end
