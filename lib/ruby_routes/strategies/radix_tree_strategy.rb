# frozen_string_literal: true

require_relative '../radix_tree'

module RubyRoutes
  module Strategies
    # RadixTreeStrategy
    #
    # Encapsulates RadixTree-based route matching.
    class RadixTreeStrategy
      def initialize
        @radix_tree = RadixTree.new
      end

      def add(route)
        @radix_tree.add(route.path, route.methods, route)
      end

      def find(path, http_method)
        @radix_tree.find(path, http_method)
      end
    end
  end
end
