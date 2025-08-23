module RubyRoutes
  module Utility
    module MethodUtility
      # Fast tables
      SYMBOL_MAP = {
        get:    'GET'.freeze,
        post:   'POST'.freeze,
        put:    'PUT'.freeze,
        patch:  'PATCH'.freeze,
        delete: 'DELETE'.freeze,
        head:   'HEAD'.freeze,
        options:'OPTIONS'.freeze
      }.freeze

      # Cache for arbitrary/custom verbs (e.g. WebDAV) or lower/mixed case strings
      METHOD_CACHE = {}

      # Public: normalize any HTTP method-ish input to its canonical uppercase String.
      # Avoids String#upcase; performs single-pass ASCII upcasing when needed, caching result.
      def normalize_http_method(method)
        case method
        when String
          return method if already_upper_ascii?(method)
          METHOD_CACHE[method] ||= ascii_upcase(method).freeze
        when Symbol
          SYMBOL_MAP[method] || (METHOD_CACHE[method] ||= ascii_upcase(method.to_s).freeze)
        else
          s = method.to_s
          return s if already_upper_ascii?(s)
          METHOD_CACHE[s] ||= ascii_upcase(s).freeze
        end
      end

      private

      # Fast check: all chars A-Z (ASCII only)
      def already_upper_ascii?(str)
        str.each_byte { |b| return false if b >= 97 && b <= 122 } # a-z
        true
      end

      # Manual ASCII uppercasing (only alter a-z)
      def ascii_upcase(str)
        bytes = str.bytes
        mutated = false
        bytes.each_with_index do |b,i|
          if b >= 97 && b <= 122
            bytes[i] = b - 32
            mutated = true
          end
        end
        return str if !mutated
        bytes.pack('C*')
      end
    end
  end
end
