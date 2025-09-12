# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Integration Tests' do
  def skip_if_hash_based_strategy(router, message = 'HashBasedStrategy does not support dynamic routes')
    if router.route_set.instance_variable_get(:@strategy).is_a?(RubyRoutes::Strategies::HashBasedStrategy)
      skip message
    end
  end

  describe 'Full routing workflow' do
    let(:hash_based_router) do
      RubyRoutes::Router.new do
        root to: 'home#index'

        resources :users do
          resources :posts do
            resources :comments
          end
        end

        namespace :api do
          namespace :v1 do
            resources :users, only: %i[index show]
            get '/status', to: 'status#show'
          end
        end

        scope constraints: { id: /\d+/ } do
          get '/items/:id', to: 'items#show', as: :item
        end

        concern :commentable do
          resources :comments, only: %i[index create]
        end

        resources :articles do
          concerns :commentable
        end

        get '/search', to: 'search#index', as: :search
        match '/contact', to: 'pages#contact', via: %i[get post], as: :contact
      end.finalize!
    end

    describe 'route matching' do
      it 'matches root route' do
        result = hash_based_router.route_set.match('GET', '/')
        expect(result).not_to be_nil
        expect(result[:controller]).to eq('home')
        expect(result[:action]).to eq('index')
      end

      it 'matches RESTful resource routes' do
        skip_if_hash_based_strategy(hash_based_router)

        # Index
        result = hash_based_router.route_set.match('GET', '/users')
        expect(result[:controller]).to eq('users')
        expect(result[:action]).to eq('index')

        # Show
        result = hash_based_router.route_set.match('GET', '/users/123')
        expect(result[:controller]).to eq('users')
        expect(result[:action]).to eq('show')
        expect(result[:params]['id']).to eq('123')

        # Create
        result = hash_based_router.route_set.match('POST', '/users')
        expect(result[:controller]).to eq('users')
        expect(result[:action]).to eq('create')

        # Update
        result = hash_based_router.route_set.match('PUT', '/users/123')
        expect(result[:controller]).to eq('users')
        expect(result[:action]).to eq('update')
        expect(result[:params]['id']).to eq('123')

        # Delete
        result = hash_based_router.route_set.match('DELETE', '/users/123')
        expect(result[:controller]).to eq('users')
        expect(result[:action]).to eq('destroy')
        expect(result[:params]['id']).to eq('123')
      end

      it 'matches nested resource routes' do
        skip_if_hash_based_strategy(hash_based_router)

        # Nested posts
        result = hash_based_router.route_set.match('GET', '/users/123/posts')
        expect(result[:controller]).to eq('posts')
        expect(result[:action]).to eq('index')

        # Deeply nested comments
        result = hash_based_router.route_set.match('GET', '/users/123/posts/456/comments')
        expect(result[:controller]).to eq('comments')
        expect(result[:action]).to eq('index')

        result = hash_based_router.route_set.match('POST', '/users/123/posts/456/comments')
        expect(result[:controller]).to eq('comments')
        expect(result[:action]).to eq('create')
      end

      it 'matches namespaced routes' do
        skip_if_hash_based_strategy(hash_based_router)

        result = hash_based_router.route_set.match('GET', '/api/v1/users')
        expect(result[:controller]).to eq('api/v1/users')
        expect(result[:action]).to eq('index')

        result = hash_based_router.route_set.match('GET', '/api/v1/users/123')
        expect(result[:controller]).to eq('api/v1/users')
        expect(result[:action]).to eq('show')
        expect(result[:params]['id']).to eq('123')

        result = hash_based_router.route_set.match('GET', '/api/v1/status')
        expect(result[:controller]).to eq('api/v1/status')
        expect(result[:action]).to eq('show')
      end

      it 'respects route constraints' do
        skip_if_hash_based_strategy(hash_based_router)

        # Should match numeric ID
        result = hash_based_router.route_set.match('GET', '/items/123')
        expect(result).not_to be_nil
        expect(result[:controller]).to eq('items')
        expect(result[:params]['id']).to eq('123')

        # Should not match non-numeric ID
        result = hash_based_router.route_set.match('GET', '/items/abc')
        expect(result).to be_nil
      end

      it 'matches concern routes' do
        skip_if_hash_based_strategy(hash_based_router)

        # Comments on articles via concern
        result = hash_based_router.route_set.match('GET', '/articles/123/comments')
        expect(result[:controller]).to eq('comments')
        expect(result[:action]).to eq('index')

        result = hash_based_router.route_set.match('POST', '/articles/123/comments')
        expect(result[:controller]).to eq('comments')
        expect(result[:action]).to eq('create')
      end

      it 'matches custom routes with multiple HTTP methods' do
        result = hash_based_router.route_set.match('GET', '/contact')
        expect(result[:controller]).to eq('pages')
        expect(result[:action]).to eq('contact')

        result = hash_based_router.route_set.match('POST', '/contact')
        expect(result[:controller]).to eq('pages')
        expect(result[:action]).to eq('contact')

        # Should not match other methods
        result = hash_based_router.route_set.match('PUT', '/contact')
        expect(result).to be_nil
      end
    end

    describe 'path generation' do
      it 'generates paths for named routes' do
        skip_if_hash_based_strategy(hash_based_router)

        # Simple named route
        path = hash_based_router.route_set.generate_path(:search)
        expect(path).to eq('/search')

        # Named route with parameters
        path = hash_based_router.route_set.generate_path(:item, id: '123')
        expect(path).to eq('/items/123')

        # Contact route
        path = hash_based_router.route_set.generate_path(:contact)
        expect(path).to eq('/contact')
      end

      it 'generates paths for RESTful routes' do
        skip_if_hash_based_strategy(hash_based_router)

        routes = hash_based_router.route_set.routes

        # Test user show route
        user_show_route = routes.find { |r| r.path == '/users/:id' && r.methods.include?('GET') }
        expect(user_show_route).not_to be_nil
        path = hash_based_router.route_set.generate_path_from_route(user_show_route, id: '123')
        expect(path).to eq('/users/123')

        # Test user index route
        user_index_route = routes.find { |r| r.path == '/users' && r.methods.include?('GET') }
        expect(user_index_route).not_to be_nil
        path = hash_based_router.route_set.generate_path_from_route(user_index_route)
        expect(path).to eq('/users')

        # Test nested route (posts under users)
        nested_route = routes.find { |r| r.path == '/users/:id/posts' && r.methods.include?('GET') }
        expect(nested_route).not_to be_nil
        path = hash_based_router.route_set.generate_path_from_route(nested_route, id: '456')
        expect(path).to eq('/users/456/posts')
      end
    end

    describe 'performance with realistic load' do
      it 'handles many route matches efficiently' do
        skip_if_hash_based_strategy(hash_based_router)

        paths = [
          '/',
          '/users',
          '/users/123',
          '/users/123/posts',
          '/users/123/posts/456',
          '/api/v1/users',
          '/api/v1/users/789',
          '/items/999',
          '/search',
          '/contact'
        ]

        # Warm up cache
        paths.each { |path| hash_based_router.route_set.match('GET', path) }

        # Measure performance
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        1000.times do
          paths.each { |path| hash_based_router.route_set.match('GET', path) }
        end
        end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        # Should complete quickly (less than 2 seconds for 10,000 matches on CI)
        expect(end_time - start_time).to be < 2.0
        # Should have good cache hit rate
        stats = hash_based_router.route_set.cache_stats
        expect(stats[:hits]).to be > 0
      end

      it 'handles cache eviction gracefully' do
        skip_if_hash_based_strategy(hash_based_router)

        # Generate many unique paths to trigger cache eviction
        1000.times do |i|
          hash_based_router.route_set.match('GET', "/users/#{i}")
        end

        # Should still work correctly after many requests
        result = hash_based_router.route_set.match('GET', '/users/123')
        expect(result[:controller]).to eq('users')
        expect(result[:action]).to eq('show')
      end
    end

    describe 'complex routing scenarios' do
      it 'handles overlapping route patterns' do
        skip_if_hash_based_strategy(hash_based_router)

        complex_hash_based_router = RubyRoutes::Router.new do
          get '/users/new', to: 'users#new'
          get '/users/:id', to: 'users#show'
          get '/users/:id/edit', to: 'users#edit'
        end

        # Should match most specific first
        result = complex_hash_based_router.route_set.match('GET', '/users/new')
        expect(result[:action]).to eq('new')

        result = complex_hash_based_router.route_set.match('GET', '/users/123')
        expect(result[:action]).to eq('show')
        expect(result[:params]['id']).to eq('123')

        result = complex_hash_based_router.route_set.match('GET', '/users/123/edit')
        expect(result[:action]).to eq('edit')
        expect(result[:params]['id']).to eq('123')
      end

      it 'handles wildcard routes' do
        skip_if_hash_based_strategy(hash_based_router)

        wildcard_hash_based_router = RubyRoutes::Router.new do
          get '/files/*path', to: 'files#show'
          get '/assets/*path', to: 'assets#show'
        end

        result = wildcard_hash_based_router.route_set.match('GET', '/files/docs/readme.txt')
        expect(result[:controller]).to eq('files')
        expect(result[:params]['path']).to eq('docs/readme.txt')

        result = wildcard_hash_based_router.route_set.match('GET', '/assets/css/style.css')
        expect(result[:controller]).to eq('assets')
        expect(result[:params]['path']).to eq('css/style.css')
      end

      it 'handles routes with defaults' do
        defaults_hash_based_router = RubyRoutes::Router.new do
          get '/posts', to: 'posts#index', defaults: { format: 'html' }
          get '/api/posts', to: 'posts#index', defaults: { format: 'json' }
        end

        result = defaults_hash_based_router.route_set.match('GET', '/posts')
        expect(result[:params]['format']).to eq('html')

        result = defaults_hash_based_router.route_set.match('GET', '/api/posts')
        expect(result[:params]['format']).to eq('json')
      end
    end

    describe 'error scenarios' do
      it 'handles non-matching routes gracefully' do
        result = hash_based_router.route_set.match('GET', '/nonexistent')
        expect(result).to be_nil

        result = hash_based_router.route_set.match('INVALID', '/users')
        expect(result).to be_nil
      end

      it 'handles malformed requests' do
        expect { hash_based_router.route_set.match('', '') }.not_to raise_error
        expect { hash_based_router.route_set.match('INVALID', '/users') }.not_to raise_error
      end
    end
  end

  describe 'Real-world usage patterns' do
    it 'simulates a typical web application routing setup' do
      app_hash_based_router = RubyRoutes::Router.new(strategy: RubyRoutes::Strategies::RadixTreeStrategy) do
        root to: 'home#index'

        # Public pages
        get '/about', to: 'pages#about'
        get '/contact', to: 'pages#contact'
        post '/contact', to: 'pages#create_contact'

        # User authentication
        get '/login', to: 'sessions#new'
        post '/login', to: 'sessions#create'
        delete '/logout', to: 'sessions#destroy'

        # User management
        resources :users, except: %i[destroy]

        # Blog functionality
        resources :posts do
          resources :comments, except: %i[show]
        end

        # Admin area
        namespace :admin do
          root to: 'dashboard#index'
          resources :users
          resources :posts
          resources :comments, only: %i[index destroy]
        end

        # API
        namespace :api do
          namespace :v1 do
            resources :posts, only: %i[index show]
            resources :users, only: [:show]
          end
        end
      end

      app_hash_based_router.route_set.instance_variable_get(:@strategy).find('/login', 'GET')

      # Test various routes - exclude dynamic routes for HashBasedStrategy
      test_cases = [
        ['GET', '/', 'home', 'index'],
        ['GET', '/about', 'pages', 'about'],
        ['POST', '/contact', 'pages', 'create_contact'],
        ['GET', '/login', 'sessions', 'new'],
        ['POST', '/login', 'sessions', 'create'],
        ['GET', '/users', 'users', 'index'],
        ['GET', '/users/123', 'users', 'show'],
        ['GET', '/posts', 'posts', 'index'],
        ['GET', '/posts/123/comments', 'comments', 'index'],
        ['POST', '/posts/123/comments', 'comments', 'create'],
        ['GET', '/admin', 'admin/dashboard', 'index'],
        ['GET', '/admin/users', 'admin/users', 'index'],
        ['GET', '/api/v1/posts', 'api/v1/posts', 'index'],
        ['GET', '/api/v1/users/123', 'api/v1/users', 'show']
      ]

      if app_hash_based_router.route_set.instance_variable_get(:@strategy).is_a?(RubyRoutes::Strategies::HashBasedStrategy)
        test_cases.reject! { |tc| tc[1].include?('123') }
      end

      test_cases.each do |method, path, expected_controller, expected_action|
        result = app_hash_based_router.route_set.match(method, path)
        expect(result).not_to be_nil, "Expected route #{method} #{path} to match"
        expect(result[:controller]).to eq(expected_controller)
        expect(result[:action]).to eq(expected_action)
      end

      # Verify total number of routes is reasonable
      expect(app_hash_based_router.route_set.size).to be > 30
    end
  end

  describe 'RadixTreeStrategy specific tests' do
    let(:radix_router) do
      RubyRoutes::Router.new(strategy: RubyRoutes::Strategies::RadixTreeStrategy) do
        root to: 'home#index'

        resources :users do
          resources :posts do
            resources :comments
          end
        end

        namespace :api do
          namespace :v1 do
            resources :users, only: %i[index show]
            get '/status', to: 'status#show'
          end
        end

        get '/search', to: 'search#index', as: :search
        match '/contact', to: 'pages#contact', via: %i[get post], as: :contact
      end.finalize!
    end

    it 'handles dynamic route matching with RadixTreeStrategy' do
      # Test static routes
      result = radix_router.route_set.match('GET', '/')
      expect(result[:controller]).to eq('home')
      expect(result[:action]).to eq('index')

      # Test dynamic routes
      result = radix_router.route_set.match('GET', '/users/123')
      expect(result[:controller]).to eq('users')
      expect(result[:action]).to eq('show')
      expect(result[:params]['id']).to eq('123')

      # Test nested dynamic routes
      result = radix_router.route_set.match('GET', '/users/123/posts/456')
      expect(result[:controller]).to eq('posts')
      expect(result[:action]).to eq('show')
      expect(result[:params]['id']).to eq('456')

      # Test namespaced routes
      result = radix_router.route_set.match('GET', '/api/v1/users/789')
      expect(result[:controller]).to eq('api/v1/users')
      expect(result[:action]).to eq('show')
      expect(result[:params]['id']).to eq('789')
    end

    it 'handles route constraints with RadixTreeStrategy' do
      constrained_router = RubyRoutes::Router.new(strategy: RubyRoutes::Strategies::RadixTreeStrategy) do
        scope constraints: { id: /\d+/ } do
          get '/items/:id', to: 'items#show', as: :item
        end
      end.finalize!

      # Should match numeric ID
      result = constrained_router.route_set.match('GET', '/items/123')
      expect(result[:controller]).to eq('items')
      expect(result[:params]['id']).to eq('123')

      # Should not match non-numeric ID
      result = constrained_router.route_set.match('GET', '/items/abc')
      expect(result).to be_nil
    end

    it 'handles wildcard routes with RadixTreeStrategy' do
      wildcard_router = RubyRoutes::Router.new(strategy: RubyRoutes::Strategies::RadixTreeStrategy) do
        get '/files/*path', to: 'files#show'
        get '/assets/*path', to: 'assets#show'
      end.finalize!

      result = wildcard_router.route_set.match('GET', '/files/docs/readme.txt')
      expect(result[:controller]).to eq('files')
      expect(result[:params]['path']).to eq('docs/readme.txt')

      result = wildcard_router.route_set.match('GET', '/assets/css/style.css')
      expect(result[:controller]).to eq('assets')
      expect(result[:params]['path']).to eq('css/style.css')
    end

    it 'performs well with many routes using RadixTreeStrategy' do
      # Create a router with many routes to test performance
      performance_router = RubyRoutes::Router.new(strategy: RubyRoutes::Strategies::RadixTreeStrategy) do
        100.times do |i|
          get "/test#{i}", to: "test#{i}#index"
          get "/test#{i}/:id", to: "test#{i}#show"
        end
      end.finalize!

      # Test a few routes
      result = performance_router.route_set.match('GET', '/test50')
      expect(result[:controller]).to eq('test50')
      expect(result[:action]).to eq('index')

      result = performance_router.route_set.match('GET', '/test25/123')
      expect(result[:controller]).to eq('test25')
      expect(result[:action]).to eq('show')
      expect(result[:params]['id']).to eq('123')
    end
  end

  describe 'HybridStrategy specific tests' do
    let(:hybrid_router) do
      RubyRoutes::Router.new(strategy: RubyRoutes::Strategies::HybridStrategy) do
        root to: 'home#index'

        resources :users do
          resources :posts do
            resources :comments
          end
        end

        namespace :api do
          namespace :v1 do
            resources :users, only: %i[index show]
            get '/status', to: 'status#show'
          end
        end

        get '/search', to: 'search#index', as: :search
        match '/contact', to: 'pages#contact', via: %i[get post], as: :contact
      end.finalize!
    end

    it 'handles static route optimization with HybridStrategy' do
      # Test static routes (should use hash lookup - O(1))
      result = hybrid_router.route_set.match('GET', '/')
      expect(result[:controller]).to eq('home')
      expect(result[:action]).to eq('index')

      result = hybrid_router.route_set.match('GET', '/search')
      expect(result[:controller]).to eq('search')
      expect(result[:action]).to eq('index')

      result = hybrid_router.route_set.match('GET', '/contact')
      expect(result[:controller]).to eq('pages')
      expect(result[:action]).to eq('contact')
    end

    it 'handles dynamic route matching with HybridStrategy' do
      # Test dynamic routes (should use radix tree lookup)
      result = hybrid_router.route_set.match('GET', '/users/123')
      expect(result[:controller]).to eq('users')
      expect(result[:action]).to eq('show')
      expect(result[:params]['id']).to eq('123')

      # Test nested dynamic routes
      result = hybrid_router.route_set.match('GET', '/users/123/posts/456')
      expect(result[:controller]).to eq('posts')
      expect(result[:action]).to eq('show')
      expect(result[:params]['id']).to eq('456')

      # Test namespaced routes
      result = hybrid_router.route_set.match('GET', '/api/v1/users/789')
      expect(result[:controller]).to eq('api/v1/users')
      expect(result[:action]).to eq('show')
      expect(result[:params]['id']).to eq('789')
    end

    it 'handles mixed static and dynamic routes with HybridStrategy' do
      # Mix of static and dynamic routes
      static_result = hybrid_router.route_set.match('GET', '/api/v1/status')
      expect(static_result[:controller]).to eq('api/v1/status')
      expect(static_result[:action]).to eq('show')

      dynamic_result = hybrid_router.route_set.match('GET', '/api/v1/users/123')
      expect(dynamic_result[:controller]).to eq('api/v1/users')
      expect(dynamic_result[:action]).to eq('show')
      expect(dynamic_result[:params]['id']).to eq('123')
    end

    it 'handles route constraints with HybridStrategy' do
      constrained_router = RubyRoutes::Router.new(strategy: RubyRoutes::Strategies::HybridStrategy) do
        scope constraints: { id: /\d+/ } do
          get '/items/:id', to: 'items#show', as: :item
        end
      end.finalize!

      # Should match numeric ID
      result = constrained_router.route_set.match('GET', '/items/123')
      expect(result[:controller]).to eq('items')
      expect(result[:params]['id']).to eq('123')

      # Should not match non-numeric ID
      result = constrained_router.route_set.match('GET', '/items/abc')
      expect(result).to be_nil
    end

    it 'handles wildcard routes with HybridStrategy' do
      wildcard_router = RubyRoutes::Router.new(strategy: RubyRoutes::Strategies::HybridStrategy) do
        get '/files/*path', to: 'files#show'
        get '/assets/*path', to: 'assets#show'
      end.finalize!

      result = wildcard_router.route_set.match('GET', '/files/docs/readme.txt')
      expect(result[:controller]).to eq('files')
      expect(result[:params]['path']).to eq('docs/readme.txt')

      result = wildcard_router.route_set.match('GET', '/assets/css/style.css')
      expect(result[:controller]).to eq('assets')
      expect(result[:params]['path']).to eq('css/style.css')
    end

    it 'performs well with mixed route types using HybridStrategy' do
      # Create a router with mixed static and dynamic routes
      performance_router = RubyRoutes::Router.new(strategy: RubyRoutes::Strategies::HybridStrategy) do
        # Static routes (hash-based)
        50.times do |i|
          get "/static#{i}", to: "static#{i}#index"
        end

        # Dynamic routes (radix tree-based)
        50.times do |i|
          get "/dynamic#{i}/:id", to: "dynamic#{i}#show"
        end
      end.finalize!

      # Test static routes (fast hash lookup)
      result = performance_router.route_set.match('GET', '/static25')
      expect(result[:controller]).to eq('static25')
      expect(result[:action]).to eq('index')

      # Test dynamic routes (radix tree lookup)
      result = performance_router.route_set.match('GET', '/dynamic25/123')
      expect(result[:controller]).to eq('dynamic25')
      expect(result[:action]).to eq('show')
      expect(result[:params]['id']).to eq('123')
    end

    it 'prioritizes static routes over dynamic routes with HybridStrategy' do
      priority_router = RubyRoutes::Router.new(strategy: RubyRoutes::Strategies::HybridStrategy) do
        # This should be found first (static)
        get '/test', to: 'static#show'

        # This should not be reached (dynamic)
        get '/test/:id', to: 'dynamic#show'
      end.finalize!

      result = priority_router.route_set.match('GET', '/test')
      expect(result[:controller]).to eq('static')
      expect(result[:action]).to eq('show')
      expect(result[:params]).to be_empty
    end
  end
end
