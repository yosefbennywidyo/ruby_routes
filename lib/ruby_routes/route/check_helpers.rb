# frozen_string_literal: true

module RubyRoutes
  class Route
    # CheckHelpers: small helpers for validating hash-form constraints.
    #
    # This module provides methods for validating various hash-form constraints,
    # such as minimum length, maximum length, format, inclusion, exclusion, and range.
    # Each method raises a `RubyRoutes::ConstraintViolation` exception if the
    # validation fails.
    module CheckHelpers
      # Check minimum length constraint.
      #
      # This method validates that the value meets the minimum length specified
      # in the constraint. If the value is shorter than the minimum length, a
      # `ConstraintViolation` is raised.
      #
      # @param constraint [Hash] The constraint hash containing `:min_length`.
      # @param value [String] The value to validate.
      # @raise [RubyRoutes::ConstraintViolation] If the value is shorter than the minimum length.
      # @return [void]
      def check_min_length(constraint, value)
        return unless (min = constraint[:min_length]) && value&.length < min

        raise RubyRoutes::ConstraintViolation, "Value too short (minimum #{constraint[:min_length]} characters)"
      end

      # Check maximum length constraint.
      #
      # This method validates that the value does not exceed the maximum length
      # specified in the constraint. If the value is longer than the maximum length,
      # a `ConstraintViolation` is raised.
      #
      # @param constraint [Hash] The constraint hash containing `:max_length`.
      # @param value [String] The value to validate.
      # @raise [RubyRoutes::ConstraintViolation] If the value exceeds the maximum length.
      # @return [void]
      def check_max_length(constraint, value)
        return unless (max = constraint[:max_length]) && value&.length > max

        raise RubyRoutes::ConstraintViolation, "Value too long (maximum #{constraint[:max_length]} characters)"
      end

      # Check format constraint.
      #
      # This method validates that the value matches the format specified in the
      # constraint. If the value does not match the format, a `ConstraintViolation`
      # is raised.
      #
      # @param constraint [Hash] The constraint hash containing `:format` (a Regexp).
      # @param value [String] The value to validate.
      # @raise [RubyRoutes::ConstraintViolation] If the value does not match the required format.
      # @return [void]
      def check_format(constraint, value)
        return unless (format = constraint[:format]) && !value&.match?(format)

        raise RubyRoutes::ConstraintViolation, 'Value does not match required format'
      end

      # Check in list constraint.
      #
      # This method validates that the value is included in the list specified
      # in the constraint. If the value is not in the list, a `ConstraintViolation`
      # is raised.
      #
      # @param constraint [Hash] The constraint hash containing `:in` (an Array).
      # @param value [String] The value to validate.
      # @raise [RubyRoutes::ConstraintViolation] If the value is not in the allowed list.
      # @return [void]
      def check_in_list(constraint, value)
        return unless constraint[:in] && !constraint[:in].include?(value)

        raise RubyRoutes::ConstraintViolation, 'Value not in allowed list'
      end

      # Check not in list constraint.
      #
      # This method validates that the value is not included in the list specified
      # in the constraint. If the value is in the forbidden list, a `ConstraintViolation`
      # is raised.
      #
      # @param constraint [Hash] The constraint hash containing `:not_in` (an Array).
      # @param value [String] The value to validate.
      # @raise [RubyRoutes::ConstraintViolation] If the value is in the forbidden list.
      # @return [void]
      def check_not_in_list(constraint, value)
        return unless constraint[:not_in]&.include?(value)

        raise RubyRoutes::ConstraintViolation, 'Value in forbidden list'
      end

      # Check range constraint.
      #
      # This method validates that the value falls within the range specified
      # in the constraint. If the value is outside the range, a `ConstraintViolation`
      # is raised.
      #
      # @param constraint [Hash] The constraint hash containing `:range` (a Range).
      # @param value [String] The value to validate.
      # @raise [RubyRoutes::ConstraintViolation] If the value is not in the allowed range.
      # @return [void]
      def check_range(constraint, value)
        range = constraint[:range]
        return unless range
        begin
          integer_value = Integer(value) # raises on nil, floats, or junk like "10abc"
        rescue ArgumentError, TypeError
          raise RubyRoutes::ConstraintViolation, 'Value not in allowed range'
        end

        raise RubyRoutes::ConstraintViolation, 'Value not in allowed range' unless range.cover?(integer_value)
      end
    end
  end
end
