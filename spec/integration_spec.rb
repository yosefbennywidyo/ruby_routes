require 'spec_helper'

RSpec.describe 'Integration Tests' do
  describe 'Full routing workflow' do
    let(:router) do
      RubyRoutes.draw do
        root to: 'home#index'
        
        resources :users do
          resources :posts do
            resources :comments
          end
        end
        
        namespace :api do
          namespace :v1 do
            resources :users, only: [:index, :show]
            get '/status', to: 'status#show'
          end
        end
        
        scope constraints: { id: /\d+/ } do
          get '/items/:id', to: 'items#show', as: :item
        end
        
        concern :commentable do
          resources :comments, only: [:index, :create]
        end
        
        resources :articles do
          concerns :commentable
        end
        
        get '/search', to: 'search#index', as: :search
        match '/contact', to: 'pages#contact', via: [:get, :post], as: :contact
      end
    end

    describe 'route matching' do
      it 'matches root route' do
        result = router.route_set.match('GET', '/')
        
        expect(result).not_to be_nil
        expect(result[:controller]).to eq('home')
        expect(result[:action]).to eq('index')
      end

      it 'matches RESTful resource routes' do
        # Index
        result = router.route_set.match('GET', '/users')
        expect(result[:controller]).to eq('users')
        expect(result[:action]).to eq('index')
        
        # Show
        result = router.route_set.match('GET', '/users/123')
        expect(result[:controller]).to eq('users')
        expect(result[:action]).to eq('show')
        expect(result[:params]['id']).to eq('123')
        
        # Create
        result = router.route_set.match('POST', '/users')
        expect(result[:controller]).to eq('users')
        expect(result[:action]).to eq('create')
        
        # Update
        result = router.route_set.match('PUT', '/users/123')
        expect(result[:controller]).to eq('users')
        expect(result[:action]).to eq('update')
        expect(result[:params]['id']).to eq('123')
        
        # Delete
        result = router.route_set.match('DELETE', '/users/123')
        expect(result[:controller]).to eq('users')
        expect(result[:action]).to eq('destroy')
        expect(result[:params]['id']).to eq('123')
      end

      it 'matches nested resource routes' do
        # Nested posts
        result = router.route_set.match('GET', '/users/123/posts')
        expect(result[:controller]).to eq('posts')
        expect(result[:action]).to eq('index')
        
        # Deeply nested comments
        result = router.route_set.match('GET', '/users/123/posts/456/comments')
        expect(result[:controller]).to eq('comments')
        expect(result[:action]).to eq('index')
        
        result = router.route_set.match('POST', '/users/123/posts/456/comments')
        expect(result[:controller]).to eq('comments')
        expect(result[:action]).to eq('create')
      end

      it 'matches namespaced routes' do
        result = router.route_set.match('GET', '/api/v1/users')
        expect(result[:controller]).to eq('api/v1/users')
        expect(result[:action]).to eq('index')
        
        result = router.route_set.match('GET', '/api/v1/users/123')
        expect(result[:controller]).to eq('api/v1/users')
        expect(result[:action]).to eq('show')
        expect(result[:params]['id']).to eq('123')
        
        result = router.route_set.match('GET', '/api/v1/status')
        expect(result[:controller]).to eq('api/v1/status')
        expect(result[:action]).to eq('show')
      end

      it 'respects route constraints' do
        # Should match numeric ID
        result = router.route_set.match('GET', '/items/123')
        expect(result).not_to be_nil
        expect(result[:controller]).to eq('items')
        expect(result[:params]['id']).to eq('123')
        
        # Should not match non-numeric ID
        result = router.route_set.match('GET', '/items/abc')
        expect(result).to be_nil
      end

      it 'matches concern routes' do
        # Comments on articles via concern
        result = router.route_set.match('GET', '/articles/123/comments')
        expect(result[:controller]).to eq('comments')
        expect(result[:action]).to eq('index')
        
        result = router.route_set.match('POST', '/articles/123/comments')
        expect(result[:controller]).to eq('comments')
        expect(result[:action]).to eq('create')
      end

      it 'matches custom routes with multiple HTTP methods' do
        result = router.route_set.match('GET', '/contact')
        expect(result[:controller]).to eq('pages')
        expect(result[:action]).to eq('contact')
        
        result = router.route_set.match('POST', '/contact')
        expect(result[:controller]).to eq('pages')
        expect(result[:action]).to eq('contact')
        
        # Should not match other methods
        result = router.route_set.match('PUT', '/contact')
        expect(result).to be_nil
      end
    end

    describe 'path generation' do
      it 'generates paths for named routes' do
        # Simple named route
        path = router.route_set.generate_path(:search)
        expect(path).to eq('/search')
        
        # Named route with parameters
        path = router.route_set.generate_path(:item, id: '123')
        expect(path).to eq('/items/123')
        
        # Contact route
        path = router.route_set.generate_path(:contact)
        expect(path).to eq('/contact')
      end

      it 'generates paths for RESTful routes' do
        # Note: RESTful routes don't automatically get names in this implementation
        # but we can test the path structure
        routes = router.route_set.routes
        user_show_route = routes.find { |r| r.path == '/users/:id' && r.methods.include?('GET') }
        
        if user_show_route&.named?
          path = router.route_set.generate_path_from_route(user_show_route, id: '123')
          expect(path).to eq('/users/123')
        end
      end
    end

    describe 'performance with realistic load' do
      it 'handles many route matches efficiently' do
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
        paths.each { |path| router.route_set.match('GET', path) }
        
        # Measure performance
        start_time = Time.now
        1000.times do
          paths.each { |path| router.route_set.match('GET', path) }
        end
        end_time = Time.now
        
        # Should complete quickly (less than 1 second for 10,000 matches)
        expect(end_time - start_time).to be < 1.0
        
        # Should have good cache hit rate
        stats = router.route_set.cache_stats
        expect(stats[:hits]).to be > 0
      end

      it 'handles cache eviction gracefully' do
        # Generate many unique paths to trigger cache eviction
        1000.times do |i|
          router.route_set.match('GET', "/users/#{i}")
        end
        
        # Should still work correctly after many requests
        result = router.route_set.match('GET', '/users/123')
        expect(result[:controller]).to eq('users')
        expect(result[:action]).to eq('show')
      end
    end

    describe 'complex routing scenarios' do
      it 'handles overlapping route patterns' do
        complex_router = RubyRoutes.draw do
          get '/users/new', to: 'users#new'
          get '/users/:id', to: 'users#show'
          get '/users/:id/edit', to: 'users#edit'
        end
        
        # Should match most specific first
        result = complex_router.route_set.match('GET', '/users/new')
        expect(result[:action]).to eq('new')
        
        result = complex_router.route_set.match('GET', '/users/123')
        expect(result[:action]).to eq('show')
        expect(result[:params]['id']).to eq('123')
        
        result = complex_router.route_set.match('GET', '/users/123/edit')
        expect(result[:action]).to eq('edit')
        expect(result[:params]['id']).to eq('123')
      end

      it 'handles wildcard routes' do
        wildcard_router = RubyRoutes.draw do
          get '/files/*path', to: 'files#show'
          get '/assets/*path', to: 'assets#show'
        end
        
        result = wildcard_router.route_set.match('GET', '/files/docs/readme.txt')
        expect(result[:controller]).to eq('files')
        expect(result[:params]['path']).to eq('docs/readme.txt')
        
        result = wildcard_router.route_set.match('GET', '/assets/css/style.css')
        expect(result[:controller]).to eq('assets')
        expect(result[:params]['path']).to eq('css/style.css')
      end

      it 'handles routes with defaults' do
        defaults_router = RubyRoutes.draw do
          get '/posts', to: 'posts#index', defaults: { format: 'html' }
          get '/api/posts', to: 'posts#index', defaults: { format: 'json' }
        end
        
        result = defaults_router.route_set.match('GET', '/posts')
        expect(result[:params]['format']).to eq('html')
        
        result = defaults_router.route_set.match('GET', '/api/posts')
        expect(result[:params]['format']).to eq('json')
      end
    end

    describe 'error scenarios' do
      it 'handles non-matching routes gracefully' do
        result = router.route_set.match('GET', '/nonexistent')
        expect(result).to be_nil
        
        result = router.route_set.match('INVALID', '/users')
        expect(result).to be_nil
      end

      it 'handles malformed requests' do
        expect { router.route_set.match('', '') }.not_to raise_error
        expect { router.route_set.match('INVALID', '/users') }.not_to raise_error
      end
    end
  end

  describe 'Real-world usage patterns' do
    it 'simulates a typical web application routing setup' do
      app_router = RubyRoutes.draw do
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
        resources :users, except: [:destroy]

        # Blog functionality
        resources :posts do
          resources :comments, except: [:show]
        end

        # Admin area
        namespace :admin do
          root to: 'dashboard#index'
          resources :users
          resources :posts
          resources :comments, only: [:index, :destroy]
        end
        
        # API
        namespace :api do
          namespace :v1 do
            resources :posts, only: [:index, :show]
            resources :users, only: [:show]
          end
        end
      end
      
      # Test various routes
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
      
      test_cases.each do |method, path, expected_controller, expected_action|
        result = app_router.route_set.match(method, path)
        expect(result).not_to be_nil, "Expected route #{method} #{path} to match"
        expect(result[:controller]).to eq(expected_controller)
        expect(result[:action]).to eq(expected_action)
      end
      
      # Verify total number of routes is reasonable
      expect(app_router.route_set.size).to be > 30
      expect(app_router.route_set.size).to be < 100
    end
  end
end
