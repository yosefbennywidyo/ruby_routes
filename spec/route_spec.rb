require 'spec_helper'

RSpec.describe RubyRoutes::Route do
  describe '#initialize' do
    it 'creates a route with basic options' do
      route = RubyRoutes::Route.new('/users', to: 'users#index')
      expect(route.path).to eq('/users')
      expect(route.methods).to eq(['GET'])
      expect(route.controller).to eq('users')
      expect(route.action).to eq('index')
    end

    it 'normalizes paths' do
      route = RubyRoutes::RadixTree.new('users', to: 'users#index')
      expect(route.path).to eq('/users')

      route = RubyRoutes::RadixTree.new('/users/', to: 'users#index')
      expect(route.path).to eq('/users')
    end

    it 'accepts custom HTTP methods' do
      route = RubyRoutes::RadixTree.new('/users', via: :post, to: 'users#create')
      expect(route.methods).to eq(['POST'])

      route = RubyRoutes::RadixTree.new('/users', via: [:get, :post], to: 'users#handle')
      expect(route.methods).to eq(['GET', 'POST'])
    end

    it 'extracts action from controller#action format' do
      route = RubyRoutes::RadixTree.new('/users', to: 'users#index')
      expect(route.action).to eq('index')
    end

    it 'accepts separate controller and action' do
      route = RubyRoutes::RadixTree.new('/users', controller: 'users', action: 'index')
      expect(route.controller).to eq('users')
      expect(route.action).to eq('index')
    end

    it 'raises error without controller' do
      expect { RubyRoutes::RadixTree.new('/users', action: 'index') }.to raise_error(RubyRoutes::InvalidRoute)
    end

    it 'raises error without action' do
      expect { RubyRoutes::RadixTree.new('/users', controller: 'users') }.to raise_error(RubyRoutes::InvalidRoute)
    end
  end

  describe '#match?' do
    let(:route) { RubyRoutes::RadixTree.new('/users/:id', to: 'users#show') }

    it 'matches correct path and method' do
      expect(route.match?('GET', '/users/123')).to be true
    end

    it 'does not match wrong method' do
      expect(route.match?('POST', '/users/123')).to be false
    end

    it 'does not match wrong path' do
      expect(route.match?('GET', '/users')).to be false
      expect(route.match?('GET', '/users/123/edit')).to be false
    end

    it 'matches with multiple HTTP methods' do
      route = RubyRoutes::RadixTree.new('/users/:id', via: [:get, :put], to: 'users#show')
      expect(route.match?('GET', '/users/123')).to be true
      expect(route.match?('PUT', '/users/123')).to be true
      expect(route.match?('POST', '/users/123')).to be false
    end
  end

  describe '#extract_params' do
    let(:route) { RubyRoutes::RadixTree.new('/users/:id/posts/:post_id', to: 'posts#show') }

    it 'extracts path parameters' do
      params = route.extract_params('/users/123/posts/456')
      expect(params).to eq({ 'id' => '123', 'post_id' => '456' })
    end

    it 'returns empty hash for non-matching path' do
      params = route.extract_params('/users/123')
      expect(params).to eq({})
    end

    it 'includes defaults' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', defaults: { format: 'html' })
      params = route.extract_params('/users/123')
      expect(params).to eq({ 'id' => '123', 'format' => 'html' })
    end
  end

  describe '#named?' do
    it 'returns true for named routes' do
      route = RubyRoutes::RadixTree.new('/users', as: :users, to: 'users#index')
      expect(route.named?).to be true
    end

    it 'returns false for unnamed routes' do
      route = RubyRoutes::RadixTree.new('/users', to: 'users#index')
      expect(route.named?).to be false
    end
  end

  describe '#resource?' do
    it 'identifies resource routes' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show')
      expect(route.resource?).to be true
    end

    it 'identifies non-resource routes' do
      route = RubyRoutes::RadixTree.new('/users', to: 'users#index')
      expect(route.resource?).to be false
    end
  end

  describe '#collection?' do
    it 'identifies collection routes' do
      route = RubyRoutes::RadixTree.new('/users', to: 'users#index')
      expect(route.collection?).to be true
    end

    it 'identifies non-collection routes' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show')
      expect(route.collection?).to be false
    end
  end
end
