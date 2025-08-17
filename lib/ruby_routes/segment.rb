require_relative 'segments/base_segment'
require_relative 'segments/dynamic_segment'
require_relative 'segments/static_segment'
require_relative 'segments/wildcard_segment'
require_relative 'constant'

module RubyRoutes
  class Segment
    def self.for(text)
      t = text.to_s
      key = t.empty? ? :default : t.getbyte(0)
      segment = RubyRoutes::Constant::SEGMENTS[key] || RubyRoutes::Constant::SEGMENTS[:default]
      segment.new(t)
    end

    def wildcard?
      false
    end
  end
end
