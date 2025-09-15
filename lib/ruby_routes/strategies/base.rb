# frozen_string_literal: true

module RubyRoutes
  module Strategies
    # Base
    #
    # Defines the interface for matching strategies.
    module Base
      def add(route)
        raise NotImplementedError, "#{self.class.name} must implement #add"
      end

      def find(path, http_method)
        raise NotImplementedError, "#{self.class.name} must implement #find"
      end
    end
  end
end
