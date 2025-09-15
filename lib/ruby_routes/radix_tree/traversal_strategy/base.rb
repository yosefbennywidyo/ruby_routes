# frozen_string_literal: true

module RubyRoutes
  class RadixTree
    module TraversalStrategy
      # Base class for all traversal strategies.
      class Base
        def initialize(finder)
          @finder = finder
        end

        def execute(_segments, _state, _method, _params, _captured_params)
          raise NotImplementedError, "#{self.class.name} must implement #execute"
        end
      end
    end
  end
end
