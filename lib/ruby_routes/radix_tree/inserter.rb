# frozen_string_literal: true

module RubyRoutes
  class RadixTree
    module Inserter
      private

      def insert_route(path_string, http_methods, route_handler)
        return route_handler if path_string.nil? || path_string.empty?
        tokens = split_path(path_string)
        node   = @root_node
        tokens.each { |tok| node = advance_node(node, tok) }
        finalize_endpoint(node, http_methods, route_handler)
        route_handler
      end

      def advance_node(current_node, token)
        case token[0]
        when ':'
          pname = token[1..]
          current_node.dynamic_child ||= build_param_node(pname)
          current_node = current_node.dynamic_child
        when '*'
          pname = token[1..]
          current_node.wildcard_child ||= build_param_node(pname)
          current_node = current_node.wildcard_child
          # wildcard consumes rest; caller will stop iterating naturally
        else
          lit = token.freeze
          current_node.static_children[lit] ||= Node.new
          current_node = current_node.static_children[lit]
        end
        current_node
      end

      def build_param_node(name)
        n = Node.new
        n.param_name = name
        n
      end

      def finalize_endpoint(node, http_methods, handler)
        node.is_endpoint = true
        http_methods.each { |m| node.handlers[m] = handler }
      end
    end
  end
end
