# frozen_string_literal: true

require 'set'

module RubyRoutes
  class Route
    # WarningHelpers: encapsulate deprecation / warning helpers.
    #
    # This module provides methods for emitting deprecation warnings for
    # deprecated features, such as `Proc` constraints, and suggests secure
    # alternatives.
    module WarningHelpers
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
        key = param.to_sym
        return if @proc_warnings_shown&.include?(key)

        @proc_warnings_shown ||= Set.new
        @proc_warnings_shown << key
        warn_proc_warning(key)
      end

      # Warn about `Proc` constraint deprecation.
      #
      # This method emits a detailed deprecation warning for `Proc` constraints,
      # explaining the security risks and suggesting secure alternatives.
      #
      # @param param [String, Symbol] The parameter name for which the warning
      #   is being emitted.
      # @return [void]
      def warn_proc_warning(param)
        warn <<~WARNING
          [DEPRECATION] Proc constraints are deprecated due to security risks.

          Parameter: #{param}; Route: #{@path}

          Secure alternatives:
          - Use regex: constraints: { #{param}: /\\A\\d+\\z/ }
          - Use built-in types: constraints: { #{param}: :int }
          - Use hash constraints: constraints: { #{param}: { min_length: 3, format: /\\A[a-z]+\\z/ } }

          Available built-in types: :int, :uuid, :email, :slug, :alpha, :alphanumeric

          This warning will become an error in a future version.
        WARNING
      end
    end
  end
end
