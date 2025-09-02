# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyRoutes::Router::ScopeHelpers do
  let(:dummy_class) do
    Class.new do
      include RubyRoutes::Router::ScopeHelpers

      def initialize
        @scope_stack = []
      end
    end
  end

  let(:scope_helper) { dummy_class.new }

  describe '#apply_module_scope' do
    let(:scope) { { module: 'admin' } }

    context 'when :to is provided' do
      it 'does not mutate the original :to value' do
        scoped_options = { to: 'users#index' }
        scope_helper.send(:apply_module_scope, scope, scoped_options)

        expect(scoped_options[:to]).to eq('admin/users#index')
      end

      it 'prepends the module to the :to value if missing' do
        scoped_options = { to: 'index' }
        scope_helper.send(:apply_module_scope, scope, scoped_options)

        expect(scoped_options[:to]).to eq('admin/index')
      end

      it 'handles :to with leading #' do
        scoped_options = { to: '#index' }
        scope_helper.send(:apply_module_scope, scope, scoped_options)

        expect(scoped_options[:to]).to eq('#index')
      end
    end

    context 'when :controller is provided' do
      it 'does not mutate the original :controller value' do
        scoped_options = { controller: 'users' }
        scope_helper.send(:apply_module_scope, scope, scoped_options)

        expect(scoped_options[:controller]).to eq('admin/users')
      end

      it 'prepends the module to the :controller value' do
        scoped_options = { controller: 'users' }
        result = scoped_options.dup
        scope_helper.send(:apply_module_scope, scope, result)

        expect(result[:controller]).to eq('admin/users')
      end
    end

    context 'when :to lacks "#"' do
      it 'guards against missing action and does not raise an error' do
        scoped_options = { to: 'users' }
        scope_helper.send(:apply_module_scope, scope, scoped_options)

        expect(scoped_options[:to]).to eq('admin/users')
      end
    end
  end

  describe '#apply_path_scope' do
    let(:scope) { { path: 'admin' } }

    it 'coerces scope[:path] to String and guards empties' do
      scope = { path: :admin } # Symbol
      scoped_path = 'users'.dup
      scope_helper.send(:apply_path_scope, scope, scoped_path)
      expect(scoped_path).to eq('/admin/users')

      scope = { path: '' } # Empty string
      scoped_path = 'users'.dup
      scope_helper.send(:apply_path_scope, scope, scoped_path)
      expect(scoped_path).to eq('users') # No change

      scope = { path: nil } # Nil
      scoped_path = 'users'.dup
      scope_helper.send(:apply_path_scope, scope, scoped_path)
      expect(scoped_path).to eq('users') # No change
    end
  end
end
