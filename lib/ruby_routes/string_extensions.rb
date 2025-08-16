class String
  def singularize
    case self
    when /ies$/
      self.sub(/ies$/, 'y')
    when /s$/
      self.sub(/s$/, '')
    else
      self
    end
  end

  def pluralize
    case self
    when /y$/
      self.sub(/y$/, 'ies')
    when /sh$/, /ch$/, /x$/, /z$/
      self + 'es'
    when /s$/
      # Words ending in 's' are already plural
      self
    else
      self + 's'
    end
  end
end
