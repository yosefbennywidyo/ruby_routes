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
        scope_path = scope[:path]&.to_s
        return if scope_path.nil? || scope_path.empty?

        parts = [scope_path, scoped_path].map { |p| p.to_s.gsub(%r{^/|/$}, '') }.reject(&:empty?)
        scoped_path.replace("/#{parts.join('/')}")
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
        module_string = scope[:module]&.to_s
        return if module_string.nil? || module_string.empty?

        if (to_val = scoped_options[:to])
          controller, action = to_val.to_s.split('#', 2)
          return if controller.nil? || controller.empty?
          scoped_options[:to] = action && !action.empty? ? "#{module_string}/#{controller}##{action}" : "#{module_string}/#{controller}"
        elsif (controller = scoped_options[:controller])
          controller_string = controller.to_s
          return if controller_string.empty?
          scoped_options[:controller] = "#{module_string}/#{controller_string}"
        end
      end

      # Apply the defaults from a scope to the given options.
      #
      # @param scope [Hash] The scope containing the defaults.
      # @param scoped_options [Hash] The options to update with the defaults.
      # @return [void]
      def apply_defaults_scope(scope, scoped_options)
        return unless scope[:defaults]

        scoped_options[:defaults] = scope[:defaults].merge(scoped_options[:defaults] || {})
      end

      # Apply the constraints from a scope to the given options.
      #
      # @param scope [Hash] The scope containing the constraints.
      # @param scoped_options [Hash] The options to update with the constraints.
      # @return [void]
      def apply_constraints_scope(scope, scoped_options)
        return unless scope[:constraints]

        scoped_options[:constraints] = scope[:constraints].merge(scoped_options[:constraints] || {})
      end

      # Get the current merged scope from the scope stack
      #
      # @return [Hash] The merged scope with combined namespaces
      def current_scope
        merged = {}
        namespace_parts = []

        @scope_stack.each do |scope|
          if scope[:namespace]
            namespace_parts << scope[:namespace].to_s
          end
          merged.merge!(scope)
        end

        # Combine namespaces for nested namespace support
        if namespace_parts.any?
          merged[:namespace] = namespace_parts.join('/')
        end

        merged
      end
    end
  end
end
