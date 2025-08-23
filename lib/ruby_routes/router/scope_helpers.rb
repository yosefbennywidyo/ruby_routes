# frozen_string_literal: true

module RubyRoutes
  class Router
    # ScopeHelpers: encapsulate scope application logic
    #
    # This module provides methods for managing and applying scopes in the routing DSL.
    # Scopes allow you to define nested paths, modules, defaults, and constraints
    # that apply to a group of routes.
    module ScopeHelpers
      private

      # Push a scope onto the scope stack.
      #
      # This method temporarily adds a scope entry to the scope stack, executes the
      # given block, and ensures the scope is removed afterward.
      #
      # @param scope_entry [Hash] The scope entry to push onto the stack.
      # @yield The block to execute within the scope.
      # @return [void]
      def push_scope(scope_entry)
        ensure_unfrozen!
        return unless block_given?

        @scope_stack.push(scope_entry)

        begin
          yield
        ensure
          @scope_stack.pop
        end
      end

      # Apply all scopes to the given path and options.
      #
      # This method iterates through the scope stack in reverse order, applying
      # path, module, defaults, and constraints from each scope to the given path
      # and options.
      #
      # @param path [String] The base path to apply scopes to.
      # @param options [Hash] The options to apply scopes to.
      # @return [Hash] The scoped options, including the updated path.
      def apply_scope(path, options)
        scoped_options = options.dup
        scoped_path    = path.to_s.dup

        @scope_stack.reverse_each do |scope|
          apply_path_scope(scope, scoped_path)
          apply_module_scope(scope, scoped_options)
          apply_defaults_scope(scope, scoped_options)
          apply_constraints_scope(scope, scoped_options)
        end

        scoped_options[:path] = scoped_path
        scoped_options
      end

      # Apply the path from a scope to the given path.
      #
      # @param scope [Hash] The scope containing the path.
      # @param scoped_path [String] The path to prepend the scope's path to.
      # @return [void]
      def apply_path_scope(scope, scoped_path)
        scoped_path.prepend(scope[:path]) if scope[:path]
      end

      # Apply the module from a scope to the given options.
      #
      # This method updates the `:to` or `:controller` option to include the module
      # from the scope.
      #
      # @param scope [Hash] The scope containing the module.
      # @param scoped_options [Hash] The options to update with the module.
      # @return [void]
      def apply_module_scope(scope, scoped_options)
        return unless scope[:module]

        if scoped_options[:to]
          controller, action = scoped_options[:to].to_s.split('#', 2)
          scoped_options[:to] = "#{scope[:module]}/#{controller}##{action}"
        elsif scoped_options[:controller]
          scoped_options[:controller].prepend("#{scope[:module]}/")
        end
      end

      # Apply the defaults from a scope to the given options.
      #
      # @param scope [Hash] The scope containing the defaults.
      # @param scoped_options [Hash] The options to update with the defaults.
      # @return [void]
      def apply_defaults_scope(scope, scoped_options)
        return unless scope[:defaults]

        scoped_options[:defaults] = (scoped_options[:defaults] || {}).merge(scope[:defaults])
      end

      # Apply the constraints from a scope to the given options.
      #
      # @param scope [Hash] The scope containing the constraints.
      # @param scoped_options [Hash] The options to update with the constraints.
      # @return [void]
      def apply_constraints_scope(scope, scoped_options)
        return unless scope[:constraints]

        scoped_options[:constraints] = (scoped_options[:constraints] || {}).merge(scope[:constraints])
      end
    end
  end
end
