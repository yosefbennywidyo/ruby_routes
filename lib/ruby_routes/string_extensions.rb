# frozen_string_literal: true

# Minimal String inflection helpers.
#
# NOTE: This is a very small, intentionally naive English inflector
# covering only a few common pluralization patterns used inside the
# routing DSL (e.g., resources / resource helpers). It is NOT a full
# replacement for ActiveSupport::Inflector and should not be relied on
# for general linguistic correctness.
#
# Supported patterns:
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
# Limitations:
# - Does not handle irregular forms (person/people, child/children, etc.).
# - Simplified handling of "z" endings (adds "zes" instead of "zzes").
# - Case‑sensitive (expects lowercase ASCII).
class String
  # Convert a plural form to a simplistic singular.
  #
  # @return [String] singularized form (may be the same object)
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
  # @return [String] pluralized form
  def pluralize
    case self
    when /y$/
      sub(/y$/, 'ies')
    when /sh$/, /ch$/, /x$/
      self + 'es'
    when /z$/
      self + 'zes'
    when /s$/
      self
    else
      self + 's'
    end
  end
end
