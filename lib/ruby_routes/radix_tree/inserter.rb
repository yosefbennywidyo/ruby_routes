# frozen_string_literal: true

module RubyRoutes
  class RadixTree
    # Inserter module for adding routes to the RadixTree.
    # Handles tokenization, node advancement, and endpoint finalization.
    module Inserter
      private

      # Inserts a route into the RadixTree for the given path and HTTP methods.
      #
      # @param path_string [String] the path to insert
      # @param http_methods [Array<String>] the HTTP methods for the route
      # @param route_handler [Object] the handler for the route
      # @return [Object] the route handler
      def insert_route(path_string, http_methods, route_handler)
        return route_handler if path_string.nil? || path_string.empty?

        tokens = split_path(path_string)
        current_node = @root
        tokens.each { |token| current_node = advance_node(current_node, token) }
        finalize_endpoint(current_node, http_methods, route_handler)
        route_handler
      end

      # Advances to the next node based on the token type.
      #
      # @param current_node [Node] the current node in the tree
      # @param token [String] the token to process
      # @return [Node] the next node
      def advance_node(current_node, token)
        case token[0]
        when ':'
          handle_dynamic(current_node, token)
        when '*'
          handle_wildcard(current_node, token)
        else
          handle_static(current_node, token)
        end
      end

      # Handles dynamic parameter tokens (e.g., :id).
      #
      # @param current_node [Node] the current node
      # @param token [String] the dynamic token
      # @return [Node] the dynamic child node
      def handle_dynamic(current_node, token)
        param_name = token[1..]
        raise ArgumentError, "Dynamic parameter name cannot be empty" if param_name.nil? || param_name.empty?
        current_node.dynamic_child ||= build_param_node(param_name)
        current_node.dynamic_child
      end

      # Handles wildcard tokens (e.g., *splat).
      #
      # @param current_node [Node] the current node
      # @param token [String] the wildcard token
      # @return [Node] the wildcard child node
      def handle_wildcard(current_node, token)
        param_name = token[1..]
        param_name = 'splat' if param_name.nil? || param_name.empty?
        current_node.wildcard_child ||= build_param_node(param_name)
        current_node.wildcard_child
      end

      # Handles static literal tokens.
      #
      # @param current_node [Node] the current node
      # @param token [String] the static token
      # @return [Node] the static child node
      def handle_static(current_node, token)
        literal_token = token.freeze
        current_node.static_children[literal_token] ||= Node.new
        current_node.static_children[literal_token]
      end

      # Builds a new node for parameter capture.
      #
      # @param param_name [String] the parameter name
      # @return [Node] the new parameter node
      def build_param_node(param_name)
        node = Node.new
        node.param_name = param_name
        node
      end

      # Finalizes the endpoint by adding handlers for HTTP methods.
      #
      # @param node [Node] the endpoint node
      # @param http_methods [Array<String>] the HTTP methods
      # @param route_handler [Object] the route handler
      def finalize_endpoint(node, http_methods, route_handler)
        http_methods.each { |http_method| node.add_handler(http_method, route_handler) }
      end
    end
  end
end
