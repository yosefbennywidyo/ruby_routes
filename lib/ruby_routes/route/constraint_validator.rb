# frozen_string_literal: true

require_relative '../constant'

module RubyRoutes
  class Route
    # ConstraintValidator: extracted constraint logic.
    #
    # This module provides methods for validating route constraints, including
    # support for regular expressions, procs, hash-based constraints, and built-in
    # validation rules. It also handles timeouts and raises appropriate exceptions
    # for constraint violations.
    module ConstraintValidator
      # Validate all constraints for the given parameters.
      #
      # This method iterates through all constraints and validates each parameter
      # against its corresponding rule.
      #
      # @param params [Hash] The parameters to validate.
      # @return [void]
      def validate_constraints_fast!(params)
        @constraints.each do |key, rule|
          param_key = key.to_s
          next unless params.key?(param_key)

          validate_constraint_for(rule, key, params[param_key])
        end
      end

      # Dispatch a single constraint check.
      #
      # This method validates a single parameter against its constraint rule.
      #
      # @param rule [Object] The constraint rule (Regexp, Proc, Symbol, Hash).
      # @param key [String, Symbol] The parameter key.
      # @param value [Object] The value to validate.
      # @return [void]
      def validate_constraint_for(rule, key, value)
        case rule
        when Regexp then validate_regexp_constraint(rule, value)
        when Proc then validate_proc_constraint(key, rule, value)
        when Hash then validate_hash_constraint!(rule, value.to_s)
        else
          validate_builtin_constraint(rule, value)
        end
      end

      # Handle built-in symbol/string rules via a simple lookup.
      #
      # @param rule [Symbol, String] The built-in constraint rule.
      # @param value [Object] The value to validate.
      # @return [void]
      def validate_builtin_constraint(rule, value)
        method_sym = RubyRoutes::Constant::BUILTIN_VALIDATORS[rule.to_sym] if rule
        send(method_sym, value) if method_sym
      end

      # Validate a regexp constraint.
      #
      # This method validates a value against a regular expression constraint.
      # It raises a timeout error if the validation takes too long.
      #
      # @param regexp [Regexp] The regular expression to match.
      # @param value [Object] The value to validate.
      # @raise [RubyRoutes::ConstraintViolation] If the value does not match the regexp.
      def validate_regexp_constraint(regexp, value)
        Timeout.timeout(0.1) { invalid! unless regexp.match?(value.to_s) }
      rescue Timeout::Error
        raise RubyRoutes::ConstraintViolation, 'Regex constraint timed out'
      end

      # Validate a proc constraint.
      #
      # This method validates a value using a proc constraint. It emits a
      # deprecation warning for proc constraints and handles timeouts and errors.
      #
      # @param key [String, Symbol] The parameter key.
      # @param proc [Proc] The proc to call.
      # @param value [Object] The value to validate.
      # @raise [RubyRoutes::ConstraintViolation] If the proc constraint fails or times out.
      def validate_proc_constraint(key, proc, value)
        warn_proc_constraint_deprecation(key)
        Timeout.timeout(0.05) { invalid! unless proc.call(value.to_s) }
      rescue Timeout::Error
        raise RubyRoutes::ConstraintViolation, 'Proc constraint timed out'
      rescue StandardError => e
        raise RubyRoutes::ConstraintViolation, "Proc constraint failed: #{e.message}"
      end

      # Validate an integer constraint.
      #
      # @param value [Object] The value to validate.
      # @raise [RubyRoutes::ConstraintViolation] If the value is not an integer.
      def validate_int_constraint(value)
        invalid! unless value.to_s.match?(/\A\d+\z/)
      end

      # Validate a UUID constraint.
      #
      # @param value [Object] The value to validate.
      # @raise [RubyRoutes::ConstraintViolation] If the value is not a valid UUID.
      def validate_uuid_constraint(value)
        validate_uuid!(value)
      end

      # Validate an email constraint.
      #
      # @param value [Object] The value to validate.
      # @raise [RubyRoutes::ConstraintViolation] If the value is not a valid email.
      def validate_email_constraint(value)
        invalid! unless value.to_s.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
      end

      # Validate a slug constraint.
      #
      # @param value [Object] The value to validate.
      # @raise [RubyRoutes::ConstraintViolation] If the value is not a valid slug.
      def validate_slug_constraint(value)
        invalid! unless value.to_s.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)
      end

      # Validate an alpha constraint.
      #
      # @param value [Object] The value to validate.
      # @raise [RubyRoutes::ConstraintViolation] If the value is not alphabetic.
      def validate_alpha_constraint(value)
        invalid! unless value.to_s.match?(/\A[a-zA-Z]+\z/)
      end

      # Validate an alphanumeric constraint.
      #
      # @param value [Object] The value to validate.
      # @raise [RubyRoutes::ConstraintViolation] If the value is not alphanumeric.
      def validate_alphanumeric_constraint(value)
        invalid! unless value.to_s.match?(/\A[a-zA-Z0-9]+\z/)
      end

      # Validate a UUID.
      #
      # This method validates that a value is a properly formatted UUID.
      #
      # @param value [Object] The value to validate.
      # @raise [RubyRoutes::ConstraintViolation] If the value is not a valid UUID.
      def validate_uuid!(value)
        string = value.to_s
        unless string.length == 36 && string.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
          invalid!
        end
      end

      # Raise a constraint violation.
      #
      # @raise [RubyRoutes::ConstraintViolation] Always raises this exception.
      def invalid!
        raise RubyRoutes::ConstraintViolation
      end
    end
  end
end
