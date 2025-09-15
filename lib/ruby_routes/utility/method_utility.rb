# frozen_string_literal: true

require_relative '../constant'
require_relative '../route/small_lru'

module RubyRoutes
  module Utility
    # MethodUtility
    #
    # High‑performance HTTP method normalization avoiding core
    # `String#upcase` allocations. Supports `String`, `Symbol`, and
    # arbitrary objects (coerced via `#to_s`).
    #
    # Features:
    # - Zero cost for already‑uppercase ASCII strings (fast scan).
    # - Manual ASCII uppercasing (single pass) for `a–z` only.
    # - Symbol fast path via interned constant map (`SYMBOL_MAP`).
    # - Cache (`METHOD_CACHE`) for uncommon verbs or dynamic inputs.
    #
    # Thread Safety:
    # - `METHOD_CACHE` is a shared `Hash`; occasional benign race
    #   (double compute of the same key) is acceptable. If strict
    #   thread safety is required, wrap in a `Mutex` (not done to
    #   preserve performance).
    #
    # @api internal
    module MethodUtility
      # Pre‑interned canonical uppercase strings for common verbs.
      #
      # @return [Hash{Symbol => String}]
      SYMBOL_MAP = {
        get: RubyRoutes::Constant::HTTP_GET,
        post: RubyRoutes::Constant::HTTP_POST,
        put: RubyRoutes::Constant::HTTP_PUT,
        patch: RubyRoutes::Constant::HTTP_PATCH,
        delete: RubyRoutes::Constant::HTTP_DELETE,
        head: RubyRoutes::Constant::HTTP_HEAD,
        options: RubyRoutes::Constant::HTTP_OPTIONS
      }.freeze

      # Cache for non‑predefined or previously seen method tokens.
      # Now uses SmallLru for LRU eviction instead of simple clearing.
      #
      # @return [SmallLru]
      METHOD_CACHE = RubyRoutes::Route::SmallLru.new(RubyRoutes::Constant::CACHE_SIZE)

      # Normalize an HTTP method‑like input to a canonical uppercase `String`.
      #
      # Fast paths:
      # - Uppercase ASCII `String`: returned as‑is (no dup/freeze).
      # - `Symbol` in `SYMBOL_MAP`: constant returned.
      #
      # Slow path:
      # - Manual ASCII uppercasing (only `a–z`) + cached.
      #
      # @param method_input [String, Symbol, #to_s] The HTTP method input.
      # @return [String] Canonical uppercase representation.
      #   (Cached/transformed values are frozen; uppercase fast-path may return the original `String`.)
      def normalize_http_method(method_input)
        case method_input
        when String
          normalize_string_method(method_input)
        when Symbol
          normalize_symbol_method(method_input)
        else
          normalize_other_method(method_input)
        end
      end

      private

      def cache_normalized_method(input_string)
        return input_string if already_upper_ascii?(input_string)

        # Use SmallLru for LRU eviction, freeze key to prevent mutation
        key = input_string.dup.freeze
        METHOD_CACHE.get(key) || METHOD_CACHE.set(key, ascii_upcase(input_string.dup).freeze)
      end

      # Normalize a `String` HTTP method.
      #
      # @param method_input [String] The HTTP method input.
      # @return [String] The normalized HTTP method.
      def normalize_string_method(method_input)
        cache_normalized_method(method_input)
      end

      # Normalize a `Symbol` HTTP method.
      #
      # @param method_input [Symbol] The HTTP method input.
      # @return [String] The normalized HTTP method.
      def normalize_symbol_method(method_input)
        SYMBOL_MAP[method_input] || begin
          key = method_input.to_s.freeze
          METHOD_CACHE.get(key) || METHOD_CACHE.set(key, ascii_upcase(method_input.to_s).freeze)
        end
      end

      # Normalize an arbitrary HTTP method input.
      #
      # @param method_input [#to_s] The HTTP method input.
      # @return [String] The normalized HTTP method.
      def normalize_other_method(method_input)
        coerced = method_input.to_s
        cache_normalized_method(coerced)
      end

      # Determine if a `String` consists solely of uppercase ASCII (`A–Z`) or non‑letters.
      #
      # @param candidate [String] The string to check.
      # @return [Boolean] `true` if the string is already uppercase ASCII, `false` otherwise.
      def already_upper_ascii?(candidate)
        candidate.each_byte { |char_code| return false if char_code >= 97 && char_code <= 122 } # a-z
        true
      end

      # Convert only ASCII lowercase letters (`a–z`) to uppercase in a single pass.
      #
      # Returns the original `String` when no changes are needed to avoid allocation.
      #
      # @param original [String] The original string.
      # @return [String] Either the original or a newly packed transformed string.
      def ascii_upcase(original)
        byte_array = original.bytes
        any_lowercase_transformed = false
        byte_array.each_with_index do |char_code, idx|
          if char_code >= 97 && char_code <= 122
            byte_array[idx] = char_code - 32
            any_lowercase_transformed = true
          end
        end
        return original unless any_lowercase_transformed

        byte_array.pack('C*')
      end
    end
  end
end
