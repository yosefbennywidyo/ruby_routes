# frozen_string_literal: true

require 'spec_helper'
require 'ruby_routes/strategies/hybrid_strategy'

RSpec.describe RubyRoutes::Strategies::HybridStrategy do
  let(:strategy) { described_class.new }
  let(:static_route) { double('Route', path: '/users', methods: ['GET']) }
  let(:dynamic_route) { double('Route', path: '/users/:id', methods: ['GET']) }

  describe '#add' do
    it 'adds static routes to hash storage' do
      strategy.add(static_route)
      expect(strategy.find('/users', 'GET')).to eq([static_route, {}])
    end

    it 'adds dynamic routes to radix tree storage' do
      strategy.add(dynamic_route)
      result = strategy.find('/users/42', 'GET')
      expect(result).not_to be_nil
      route, params = result
      expect(route).to be(dynamic_route)
      expect(params).to include('id' => '42')
    end
  end

  describe '#find' do
    before do
      strategy.add(static_route)
    end

    it 'finds static routes quickly' do
      result = strategy.find('/users', 'GET')
      expect(result).to eq([static_route, {}])
    end

    it 'returns nil for unmatched paths' do
      result = strategy.find('/nonexistent', 'GET')
      expect(result).to be_nil
    end
  end
end
