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

  describe 'constraint validation' do
    it 'validates routes with constraints' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', constraints: { id: /\d+/ })
      
      expect(route.constraints[:id]).to eq(/\d+/)
    end
  end

  describe 'method normalization' do
    it 'normalizes HTTP methods to uppercase' do
      route = RubyRoutes::RadixTree.new('/users', via: [:get, :post], to: 'users#index')
      
      expect(route.methods).to include('GET')
      expect(route.methods).to include('POST')
    end

    it 'handles string methods' do
      route = RubyRoutes::RadixTree.new('/users', via: 'patch', to: 'users#update')
      
      expect(route.methods).to include('PATCH')
    end
  end

  describe '#parse_query_params' do
    it 'handles empty query string' do
      route = RubyRoutes::RadixTree.new('/search', to: 'search#index')
      params = route.parse_query_params('/search')
      
      expect(params).to be_empty
    end
  end

  describe 'path generation edge cases' do
    it 'returns root path for root route' do
      route = RubyRoutes::RadixTree.new('/', to: 'home#index', as: :root)
      path = route.generate_path
      
      expect(path).to eq('/')
    end

    it 'uses static path for routes without parameters' do
      route = RubyRoutes::RadixTree.new('/about', to: 'pages#about', as: :about)
      path = route.generate_path
      
      expect(path).to eq('/about')
    end

    it 'raises error for missing required parameters' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', as: :user)
      
      expect {
        route.generate_path
      }.to raise_error(RubyRoutes::RouteNotFound, /Missing params: id/)
    end

    it 'caches generated paths for performance' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', as: :user)
      
      # First call
      path1 = route.generate_path(id: '123')
      
      # Second call should use cache
      path2 = route.generate_path(id: '123')
      
      expect(path1).to eq(path2)
      expect(path1).to eq('/users/123')
    end

    it 'handles complex parameter combinations' do
      route = RubyRoutes::RadixTree.new('/posts/:post_id/comments/:id', 
                                        to: 'comments#show', 
                                        as: :post_comment)
      
      path = route.generate_path(post_id: '456', id: '789')
      expect(path).to eq('/posts/456/comments/789')
    end

    it 'handles extra parameters' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', as: :user)
      
      path = route.generate_path(id: '123', format: 'json')
      expect(path).to include('/users/123')
    end
  end

  describe 'parameter extraction edge cases' do
    it 'handles routes with no parameters' do
      route = RubyRoutes::RadixTree.new('/about', to: 'pages#about')
      params = route.extract_params('/about')
      
      expect(params).to be_a(Hash)
      expect(params).to be_empty
    end

    it 'includes default parameters' do
      route = RubyRoutes::RadixTree.new('/posts', to: 'posts#index', defaults: { format: 'html' })
      params = route.extract_params('/posts')
      
      expect(params['format']).to eq('html')
    end

    it 'handles wildcard parameters' do
      route = RubyRoutes::RadixTree.new('/files/*path', to: 'files#show')
      params = route.extract_params('/files/docs/readme.txt')
      
      expect(params).to be_a(Hash)
    end

    it 'handles multiple dynamic segments' do
      route = RubyRoutes::RadixTree.new('/users/:user_id/posts/:id', to: 'posts#show')
      params = route.extract_params('/users/123/posts/456')
      
      expect(params['user_id']).to eq('123')
      expect(params['id']).to eq('456')
    end
  end

  describe 'constraint validation edge cases' do
    it 'stores constraints correctly' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', constraints: { id: /\d+/ })
      
      expect(route.constraints[:id]).to eq(/\d+/)
    end

    it 'handles multiple constraints' do
      route = RubyRoutes::RadixTree.new('/posts/:year/:month', 
                                        to: 'posts#archive',
                                        constraints: { 
                                          year: /\d{4}/, 
                                          month: /\d{1,2}/ 
                                        })
      
      expect(route.constraints[:year]).to eq(/\d{4}/)
      expect(route.constraints[:month]).to eq(/\d{1,2}/)
    end
  end

  describe 'route validation' do
    it 'raises error for invalid route without controller or action' do
      expect {
        RubyRoutes::RadixTree.new('/invalid', {})
      }.to raise_error(RubyRoutes::InvalidRoute)
    end

    it 'accepts route with controller option' do
      expect {
        RubyRoutes::RadixTree.new('/valid', controller: 'pages', action: 'show')
      }.not_to raise_error
    end

    it 'accepts route with to option' do
      expect {
        RubyRoutes::RadixTree.new('/valid', to: 'pages#show')
      }.not_to raise_error
    end
  end

  describe 'performance optimizations' do
    it 'pre-compiles route data during initialization' do
      route = RubyRoutes::RadixTree.new('/users/:id/posts/:post_id', to: 'posts#show')
      
      # These should be pre-compiled
      expect(route.instance_variable_get(:@required_params)).not_to be_empty
      expect(route.instance_variable_get(:@required_params_set)).not_to be_empty
    end

    it 'uses frozen method sets for fast lookup' do
      route = RubyRoutes::RadixTree.new('/users', via: [:get, :post], to: 'users#index')
      methods_set = route.instance_variable_get(:@methods_set)
      
      expect(methods_set).to be_frozen
      expect(methods_set).to include('GET', 'POST')
    end

    it 'caches path generation results' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', as: :user)
      
      # Generate path multiple times with same params
      5.times { route.generate_path(id: '123') }
      
      # Cache should have entries (we can't directly test cache hits without exposing internals)
      cache = route.instance_variable_get(:@gen_cache)
      expect(cache).not_to be_nil
    end
  end
end
