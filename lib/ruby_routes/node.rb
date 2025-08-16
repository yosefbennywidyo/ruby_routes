module RubyRoutes
  class Node
    attr_accessor :static_children, :dynamic_child, :wildcard_child,
                  :handlers, :param_name, :is_endpoint

    def initialize
      @static_children = {}
      @dynamic_child = nil
      @wildcard_child = nil
      @handlers = {}
      @param_name = nil
      @is_endpoint = false
    end

    def add_handler(method, handler)
      @handlers[method.to_s] = handler
      @is_endpoint = true
    end

    def get_handler(method)
      @handlers[method.to_s]
    end
  end
end
