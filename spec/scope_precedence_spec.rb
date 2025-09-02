# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyRoutes::Router::ScopeHelpers do
  let(:dummy_class) do
    Class.new do
      include RubyRoutes::Router::ScopeHelpers

      def initialize
        @scope_stack = []
      end

      def apply_scope_with_defaults_and_constraints(path, options)
        apply_scope(path, options)
      end
    end
  end

  let(:scope_helper) { dummy_class.new }

  describe 'scope precedence' do
    it 'ensures inner scopes override outer scopes for defaults' do
      scope_helper.instance_variable_set(:@scope_stack, [
        { defaults: { format: 'json', locale: 'en' } },
        { defaults: { locale: 'fr' } }
      ])

      options = { defaults: { timezone: 'UTC' } }
      result = scope_helper.apply_scope_with_defaults_and_constraints('/path', options)

      expect(result[:defaults]).to eq({ format: 'json', locale: 'fr', timezone: 'UTC' })
    end

    it 'ensures inner scopes override outer scopes for constraints' do
      scope_helper.instance_variable_set(:@scope_stack, [
        { constraints: { subdomain: 'www', protocol: 'http' } },
        { constraints: { protocol: 'https' } }
      ])

      options = { constraints: { port: 443 } }
      result = scope_helper.apply_scope_with_defaults_and_constraints('/path', options)

      expect(result[:constraints]).to eq({ subdomain: 'www', protocol: 'https', port: 443 })
    end
  end
end
