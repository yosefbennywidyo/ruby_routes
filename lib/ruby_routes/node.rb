# frozen_string_literal: true

require_relative 'segment'
require_relative 'utility/method_utility'
require_relative 'constant'

module RubyRoutes
  class Node
    include RubyRoutes::Utility::MethodUtility

    attr_accessor :param_name, :is_endpoint, :dynamic_child, :wildcard_child
    attr_reader :handlers, :static_children

    def initialize
      @is_endpoint      = false
      @handlers         = {}
      @static_children  = {}
      @dynamic_child    = nil
      @wildcard_child   = nil
      @param_name       = nil
    end

    def add_handler(method, handler)
      method_str            = normalize_http_method(method)
      @handlers[method_str] = handler
      @is_endpoint          = true
    end

    def get_handler(method)
      @handlers[normalize_http_method(method)]
    end

    def traverse_for(segment, index, segments, params)
      RubyRoutes::Constant::TRAVERSAL_ORDER.each do |strategy_name|
        result = RubyRoutes::Constant::TRAVERSAL_STRATEGIES[strategy_name].call(self, segment, index, segments)
        return result if result
      end

      RubyRoutes::Constant::NO_TRAVERSAL_RESULT
    end
  end
end
