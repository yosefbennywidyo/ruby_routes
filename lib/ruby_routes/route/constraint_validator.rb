# frozen_string_literal: true
module RubyRoutes
  class Route
    # ConstraintValidator: extracted constraint logic
    module ConstraintValidator

      def validate_constraints_fast!(params)
        @constraints.each do |k, rule|
          next unless params.key?(k.to_s)
          val = params[k.to_s]
          case rule
          when Regexp      then validate_regexp!(rule, val)
          when Proc        then validate_proc!(k, rule, val)
          when :int        then invalid! unless val.to_s.match?(/\A\d+\z/)
          when :uuid       then validate_uuid!(val)
          when :email      then invalid! unless val.to_s.match?(/\A[^@\s]+@[^@\s]+\.[^@\s]+\z/)
          when :slug       then invalid! unless val.to_s.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)
          when :alpha      then invalid! unless val.to_s.match?(/\A[a-zA-Z]+\z/)
          when :alphanumeric then invalid! unless val.to_s.match?(/\A[a-zA-Z0-9]+\z/)
          when Hash        then validate_hash_constraint!(rule, val.to_s)
          end
        end
      end

      def validate_regexp!(rx, val)
        Timeout.timeout(0.1) { invalid! unless rx.match?(val.to_s) }
      rescue Timeout::Error
        raise RubyRoutes::ConstraintViolation, 'Regex constraint timed out'
      end

      def validate_proc!(key, pr, val)
        warn_proc_constraint_deprecation(key)
        Timeout.timeout(0.05) { invalid! unless pr.call(val.to_s) }
      rescue Timeout::Error
        raise RubyRoutes::ConstraintViolation, 'Proc constraint timed out'
      rescue StandardError => e
        raise RubyRoutes::ConstraintViolation, "Proc constraint failed: #{e.message}"
      end

      def validate_uuid!(val)
        s = val.to_s
        invalid! unless s.length == 36 && s.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
      end

      def invalid!
        raise RubyRoutes::ConstraintViolation
      end
    end
  end
end
