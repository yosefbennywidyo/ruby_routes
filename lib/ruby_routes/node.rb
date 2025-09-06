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
      @is_endpoint = false
      @handlers = {}
      @static_children = {}
      @dynamic_child = nil
      @wildcard_child = nil
      @param_name = nil
    end

    def add_handler(method, handler)
      method_str = normalize_http_method(method)
      @handlers[method_str] = handler
      @is_endpoint = true
    end

    def get_handler(method)
      @handlers[normalize_http_method(method)]
    end

    def traverse_for(segment, index, segments, params)
      # Prioritize static matches, then dynamic, then wildcard.
      # This logic is now more aligned with the Segment strategy pattern.
      static_child = @static_children[segment]
      return [static_child, false, Constant::EMPTY_HASH] if static_child
      return [@dynamic_child, false, { @dynamic_child.param_name => segment }] if @dynamic_child
      return [@wildcard_child, true, { @wildcard_child.param_name => segments[index..-1].join('/') }] if @wildcard_child

      Constant::NO_TRAVERSAL_RESULT
    end
  end
end
