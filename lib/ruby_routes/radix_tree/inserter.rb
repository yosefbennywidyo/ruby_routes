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

        tokens = split_path_cached(path_string)
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
        Segment.for(token).ensure_child(current_node)
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
