# frozen_string_literal: true

module RubyRoutes
  module Utility
    # InflectorUtility
    #
    # Minimal internal pluralize/singularize (same logic as before).
    # Not a full linguistic inflector; avoid exposing publicly.
    module InflectorUtility
      module_function

      def singularize(str)
        return '' if str.nil?

        case str
        when /ies$/ then str.sub(/ies$/, 'y')
        when /s$/   then str.sub(/s$/, '')
        else str
        end
      end

      def pluralize(str)
        return '' if str.nil?

        case str
        when /y$/          then str.sub(/y$/, 'ies')
        when /(sh|ch|x)$/  then "#{str}es"
        when /z$/          then "#{str}zes"
        when /s$/          then str
        else                    "#{str}s"
        end
      end
    end
  end
end
