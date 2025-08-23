# frozen_string_literal: true

# Minimal String inflection helpers.
#
# @note This is a very small, intentionally naive English inflector
# covering only a few common pluralization patterns used inside the
# routing DSL (e.g., resources / resource helpers). It is NOT a full
# replacement for ActiveSupport::Inflector and should not be relied on
# for general linguistic correctness.
#
# @note Supported patterns:
# - Singularize:
#   * words ending in "ies" -> "y" (companies -> company)
#   * words ending in "s"   -> strip trailing "s" (users -> user)
# - Pluralize:
#   * words ending in "y"   -> replace with "ies" (company -> companies)
#   * words ending in sh/ch/x -> append "es" (box -> boxes)
#   * words ending in "z"   -> append "zes" (quiz -> quizzes) (simplified)
#   * words ending in "s"   -> unchanged
#   * default -> append "s"
#
# @note Limitations:
# - Does not handle irregular forms (person/people, child/children, etc.).
# - Simplified handling of "z" endings (adds "zes" instead of "zzes").
# - Case‑sensitive (expects lowercase ASCII).
#
# @api internal
class String
  # Convert a plural form to a simplistic singular.
  #
  # @example Singularize a word
  #   "companies".singularize # => "company"
  #   "users".singularize     # => "user"
  #   "box".singularize       # => "box" (unchanged)
  #
  # @return [String] Singularized form (may be the same object if no change is needed).
  def singularize
    case self
    when /ies$/
      sub(/ies$/, 'y')
    when /s$/
      sub(/s$/, '')
    else
      self
    end
  end

  # Convert a singular form to a simplistic plural.
  #
  # @example Pluralize a word
  #   "company".pluralize # => "companies"
  #   "box".pluralize     # => "boxes"
  #   "quiz".pluralize    # => "quizzes"
  #   "user".pluralize    # => "users"
  #
  # @return [String] Pluralized form.
  def pluralize
    return self if end_with?('s')
    return sub(/y$/, 'ies') if end_with?('y')
    return "#{self}es" if match?(/sh$|ch$|x$/)
    return "#{self}zes" if end_with?('z')

    "#{self}s"
  end
end
