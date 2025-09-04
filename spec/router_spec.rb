# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyRoutes::Router do
  let(:router) { RubyRoutes::Router.new }

  describe 'HTTP method routes' do
    it 'defines GET routes' do
      router.get '/users', to: 'users#index'
      route = router.route_set.routes.first

      expect(route.methods).to include('GET')
      expect(route.path).to eq('/users')
      expect(route.controller).to eq('users')
      expect(route.action).to eq('index')
    end

    it 'defines POST routes' do
      router.post '/users', to: 'users#create'
      route = router.route_set.routes.first

      expect(route.methods).to include('POST')
      expect(route.controller).to eq('users')
      expect(route.action).to eq('create')
    end

    it 'defines PUT routes' do
      router.put '/users/:id', to: 'users#update'
      route = router.route_set.routes.first

      expect(route.methods).to include('PUT')
      expect(route.path).to eq('/users/:id')
    end

    it 'defines PATCH routes' do
      router.patch '/users/:id', to: 'users#update'
      route = router.route_set.routes.first

      expect(route.methods).to include('PATCH')
    end

    it 'defines DELETE routes' do
      router.delete '/users/:id', to: 'users#destroy'
      route = router.route_set.routes.first

      expect(route.methods).to include('DELETE')
    end

    it 'defines routes with custom HTTP methods' do
      router.match '/custom', via: :options, to: 'custom#handle'
      route = router.route_set.routes.first

      expect(route.methods).to include('OPTIONS')
    end
  end

  describe 'resources' do
    it 'defines standard RESTful routes for resources' do
      router.resources :users
      routes = router.route_set.routes

      # Collection routes
      expect(routes.any? { |r| r.path == '/users' && r.action == 'index' }).to be true
      expect(routes.any? { |r| r.path == '/users/new' && r.action == 'new' }).to be true
      expect(routes.any? { |r| r.path == '/users' && r.action == 'create' && r.methods.include?('POST') }).to be true

      # Member routes
      expect(routes.any? { |r| r.path == '/users/:id' && r.action == 'show' }).to be true
      expect(routes.any? { |r| r.path == '/users/:id/edit' && r.action == 'edit' }).to be true
      expect(routes.any? { |r| r.path == '/users/:id' && r.action == 'update' && r.methods.include?('PUT') }).to be true
      expect(routes.any? do |r|
        r.path == '/users/:id' && r.action == 'update' && r.methods.include?('PATCH')
      end).to be true
      expect(routes.any? { |r| r.path == '/users/:id' && r.action == 'destroy' }).to be true
    end

    it 'defines nested resources routes correctly' do
      router.resources :posts, nested: :comments
      routes = router.route_set.routes

      # Verify nested resource routes exist
      expect(routes.any? { |r| r.path == '/posts/:id/comments' && r.action == 'index' }).to be true
      expect(routes.any? { |r| r.path == '/posts/:id/comments/new' && r.action == 'new' }).to be true
      expect(routes.any? do |r|
        r.path == '/posts/:id/comments' && r.action == 'create' && r.methods.include?('POST')
      end).to be true
      expect(routes.any? { |r| r.path == '/posts/:id/comments/:nested_id' && r.action == 'show' }).to be true
      expect(routes.any? { |r| r.path == '/posts/:id/comments/:nested_id/edit' && r.action == 'edit' }).to be true
      expect(routes.any? do |r|
        r.path == '/posts/:id/comments/:nested_id' && r.action == 'update' && r.methods.include?('PUT')
      end).to be true
      expect(routes.any? do |r|
        r.path == '/posts/:id/comments/:nested_id' && r.action == 'update' && r.methods.include?('PATCH')
      end).to be true

      # Critical test: DELETE should only map to destroy action, not update
      delete_routes = routes.select { |r| r.path == '/posts/:id/comments/:nested_id' && r.methods.include?('DELETE') }
      expect(delete_routes.size).to eq(1)
      expect(delete_routes.first.action).to eq('destroy')

      # Ensure no DELETE route maps to update action
      expect(routes.any? do |r|
        r.path == '/posts/:id/comments/:nested_id' && r.action == 'update' && r.methods.include?('DELETE')
      end).to be false
    end
  end

  describe 'resource' do
    it 'defines singular resource routes' do
      router.resource :profile
      routes = router.route_set.routes

      expect(routes.size).to eq(7)

      expect(routes.any? { |r| r.path == '/profile' && r.action == 'show' }).to be true
      expect(routes.any? { |r| r.path == '/profile/new' && r.action == 'new' }).to be true
      expect(routes.any? { |r| r.path == '/profile' && r.action == 'create' && r.methods.include?('POST') }).to be true
      expect(routes.any? { |r| r.path == '/profile/edit' && r.action == 'edit' }).to be true
      expect(routes.any? { |r| r.path == '/profile' && r.action == 'update' && r.methods.include?('PUT') }).to be true
      expect(routes.any? { |r| r.path == '/profile' && r.action == 'update' && r.methods.include?('PATCH') }).to be true
      expect(routes.any? { |r| r.path == '/profile' && r.action == 'destroy' }).to be true
    end
  end

  describe 'namespace' do
    it 'adds namespace prefix to routes' do
      router.namespace :admin do
        get '/users', to: 'users#index'
      end

      route = router.route_set.routes.first
      expect(route.path).to eq('/admin/users')
      expect(route.controller).to eq('admin/users')
      expect(route.action).to eq('index')
    end
  end

  describe 'scope' do
    it 'applies scope options to routes' do
      router.scope constraints: { id: /\d+/ } do
        get '/users/:id', to: 'users#show'
      end

      route = router.route_set.routes.first
      expect(route.constraints).to eq({ id: /\d+/ })
    end
  end

  describe 'root' do
    it 'defines root route' do
      router.root to: 'home#index'
      route = router.route_set.routes.first

      expect(route.path).to eq('/')
      expect(route.controller).to eq('home')
      expect(route.action).to eq('index')
    end
  end

  describe 'concerns' do
    it 'initializes concerns hash properly' do
      # Should not raise NoMethodError when accessing undefined concern
      expect do
        router.concerns :undefined_concern
      end.to raise_error(RuntimeError, "Concern 'undefined_concern' not found")
    end

    it 'defines and uses concerns' do
      router.concern :commentable do
        resources :comments
      end

      router.resources :posts do
        concerns :commentable
      end

      routes = router.route_set.routes
      expect(routes.any? { |r| r.path == '/posts/:id/comments' }).to be true
    end

    it 'raises error for undefined concern' do
      expect do
        router.concerns :undefined_concern
      end.to raise_error(RuntimeError, "Concern 'undefined_concern' not found")
    end

    it 'handles multiple concerns' do
      router.concern :commentable do
        resources :comments
      end

      router.concern :likeable do
        post '/like', to: 'likes#create'
      end

      router.resources :posts do
        concerns :commentable, :likeable
      end

      routes = router.route_set.routes
      expect(routes.any? { |r| r.path == '/posts/:id/comments' }).to be true
      expect(routes.any? { |r| r.path == '/posts/:id/like' }).to be true
    end

    it 'calls all specified concerns' do
      # Set up multiple concerns
      router.concern :commentable do
        post '/comments', to: 'comments#create'
      end

      router.concern :taggable do
        get '/tags', to: 'tags#index'
        post '/tags', to: 'tags#create'
      end

      router.concern :searchable do
        get '/search', to: 'search#index'
      end

      # Use multiple concerns at once
      router.resources :posts do
        concerns :commentable, :taggable, :searchable
      end

      routes = router.route_set.routes

      # Check that all concern routes were created
      expect(routes.any? { |r| r.path == '/posts/:id/comments' && r.methods.include?('POST') }).to be true
      expect(routes.any? { |r| r.path == '/posts/:id/tags' && r.methods.include?('GET') }).to be true
      expect(routes.any? { |r| r.path == '/posts/:id/tags' && r.methods.include?('POST') }).to be true
      expect(routes.any? { |r| r.path == '/posts/:id/search' && r.methods.include?('GET') }).to be true
    end

    it 'combines concerns with inline block' do
      router.concern :votable do
        post '/vote', to: 'votes#create'
      end

      # Pass both a concern name and a block
      router.resources :articles do
        concerns :votable do
          # Additional routes defined inline
          get '/stats', to: 'articles#stats'
        end
      end

      routes = router.route_set.routes

      # Verify both concern routes and block routes were created
      expect(routes.any? { |r| r.path == '/articles/:id/vote' && r.methods.include?('POST') }).to be true
      expect(routes.any? { |r| r.path == '/articles/:id/stats' && r.methods.include?('GET') }).to be true
    end

    it 'handles empty concerns list with only a block' do
      # Using concerns with just a block, no named concerns
      router.resources :products do
        concerns do
          get '/reviews', to: 'reviews#index'
        end
      end

      routes = router.route_set.routes
      expect(routes.any? { |r| r.path == '/products/:id/reviews' && r.methods.include?('GET') }).to be true
    end

    it 'raises error for each undefined concern' do
      # Test that each undefined concern raises its own error
      expect do
        router.concerns :nonexistent1, :nonexistent2
      end.to raise_error(RuntimeError, "Concern 'nonexistent1' not found")

      # Define the first concern but not the second
      router.concern :existent do
        get '/exists', to: 'exists#index'
      end

      # Now the second undefined concern should raise an error
      expect do
        router.concerns :existent, :nonexistent2
      end.to raise_error(RuntimeError, "Concern 'nonexistent2' not found")
    end

    it 'applies concerns directly in a scope' do
      router.concern :testable do
        get '/test', to: 'test#index'
      end

      router.scope '/api' do
        concerns :testable
      end

      routes = router.route_set.routes
      expect(routes.any? { |r| r.path == '/api/test' }).to be true
    end

    it 'applies concerns in the specified order' do
      counter = 0
      ordered_routes = []

      router.concern :first do
        ordered_routes << (counter += 1)
        get '/first', to: 'first#index'
      end

      router.concern :second do
        ordered_routes << (counter += 1)
        get '/second', to: 'second#index'
      end

      router.concern :third do
        ordered_routes << (counter += 1)
        get '/third', to: 'third#index'
      end

      # Use scope instead of resources for more direct testing
      router.scope '/ordered' do
        concerns :first, :second, :third
      end

      # Verify concerns were applied in order
      expect(ordered_routes).to eq([1, 2, 3])

      routes = router.route_set.routes
      expect(routes.any? { |r| r.path == '/ordered/first' }).to be true
      expect(routes.any? { |r| r.path == '/ordered/second' }).to be true
      expect(routes.any? { |r| r.path == '/ordered/third' }).to be true
    end

    # Add a dedicated test for resources + concerns
    it 'applies concerns within resources' do
      router.concern :commentable do
        get '/comments', to: 'comments#index'
        post '/comments', to: 'comments#create'
      end

      router.resources :posts do
        concerns :commentable
      end

      routes = router.route_set.routes
      # Look for paths that match the pattern, with more flexible matching
      expect(routes.any? do |r|
        r.path.include?('/posts/') && r.path.include?('/comments') && r.methods.include?('GET')
      end).to be true
      expect(routes.any? do |r|
        r.path.include?('/posts/') && r.path.include?('/comments') && r.methods.include?('POST')
      end).to be true
    end

    it 'raises error for undefined concerns' do
      expect do
        router.concerns :nonexistent
      end.to raise_error(RuntimeError, /Concern.*not found/)
    end
  end

  describe '#mount' do
    it 'mounts an application at a path' do
      app = double('app')
      router.mount(app, at: '/api')

      route = router.route_set.routes.first
      expect(route.path).to eq('/api/*path')
    end

    it 'mounts with default path based on app name' do
      router.mount('MyApp')

      route = router.route_set.routes.first
      expect(route.path).to eq('/MyApp/*path')
    end
  end

  describe 'nested resources with block' do
    it 'handles nested resources with block' do
      router.resources :categories do
        resources :products
      end

      routes = router.route_set.routes
      expect(routes.any? { |r| r.path == '/categories/:id/products' }).to be true
      expect(routes.any? { |r| r.path == '/categories/:id/products/:id' }).to be true
    end
  end

  describe 'scope combinations' do
    it 'handles nested scopes' do
      router.scope path: '/api' do
        scope path: '/v1' do
          get '/users', to: 'users#index'
        end
      end

      route = router.route_set.routes.first
      expect(route.path).to eq('/api/v1/users')
    end

    it 'avoids double slashes when composing scoped paths' do
      # Test case: scope path ends with '/', route path starts with '/'
      router1 = RubyRoutes::Router.new
      router1.scope path: '/admin/' do
        router1.get '/users', to: 'users#index'
      end
      route = router1.route_set.routes.first
      expect(route.path).to eq('/admin/users')

      # Test case: scope path doesn't end with '/', route path starts with '/'
      router2 = RubyRoutes::Router.new
      router2.scope path: '/admin' do
        router2.get '/users', to: 'users#index'
      end
      route = router2.route_set.routes.first
      expect(route.path).to eq('/admin/users')

      # Test case: scope path ends with '/', route path doesn't start with '/'
      router3 = RubyRoutes::Router.new
      router3.scope path: '/admin/' do
        router3.get 'users', to: 'users#index'
      end
      route = router3.route_set.routes.first
      expect(route.path).to eq('/admin/users')

      # Test case: neither path has slashes
      router4 = RubyRoutes::Router.new
      router4.scope path: 'admin' do
        router4.get 'users', to: 'users#index'
      end
      route = router4.route_set.routes.first
      expect(route.path).to eq('/admin/users')
    end
  end

  describe 'resources with custom path and controller' do
    it 'generates correct routes and controller/action mapping' do
      router = RubyRoutes::Router.new do
        resources :regulations, path: 'peraturan', controller: 'regulations', only: %i[index show]
      end

      routes = router.route_set.routes

      # Should generate /peraturan for index
      index_route = routes.find { |r| r.path == '/peraturan' && r.methods.include?('GET') }
      expect(index_route).not_to be_nil
      expect(index_route.controller).to eq('regulations')
      expect(index_route.action).to eq('index')

      # Should generate /peraturan/:id for show
      show_route = routes.find { |r| r.path == '/peraturan/:id' && r.methods.include?('GET') }
      expect(show_route).not_to be_nil
      expect(show_route.controller).to eq('regulations')
      expect(show_route.action).to eq('show')
    end
  end

  describe '#namespace' do
    it 'executes the block in the router context' do
      router = RubyRoutes.draw do
        namespace :admin do
          get '/dashboard', to: 'dashboard#index'
        end
      end

      # Verify the route was created with the namespace applied
      route = router.route_set.routes.first
      expect(route.path).to eq('/admin/dashboard')
      expect(route.controller).to eq('admin/dashboard')
      expect(route.action).to eq('index')
    end

    it 'supports nested namespaces' do
      router = RubyRoutes.draw do
        namespace :admin do
          namespace :reports do
            get '/summary', to: 'summary#index'
          end
        end
      end

      route = router.route_set.routes.first
      expect(route.path).to eq('/admin/reports/summary')
      expect(route.controller).to eq('admin/reports/summary')
      expect(route.action).to eq('index')
    end

    describe '#namespace' do
      it 'pushes namespace scope onto scope_stack' do
        router = RubyRoutes::Router.new

        # Verify empty scope stack before
        expect(router.instance_variable_get(:@scope_stack).size).to eq(0)

        # Use a variable to capture stack state from inside the block
        stack_size_inside_block = nil
        current_scope_inside_block = nil

        # Call namespace with a block that captures information
        router.namespace(:admin) do
          # Store the current state in variables
          stack_size_inside_block = @scope_stack.size
          current_scope_inside_block = @scope_stack.last
        end

        # Verify the scope stack is empty after exiting the block
        expect(router.instance_variable_get(:@scope_stack).size).to eq(0)

        # Check that the variables captured the correct information
        expect(stack_size_inside_block).to eq(1)
        expect(current_scope_inside_block[:path]).to eq('/admin')
        expect(current_scope_inside_block[:module]).to eq(:admin)
      end
    end
  end

  describe 'PathUtility#join_path_parts' do
    let(:utility) { Class.new { extend RubyRoutes::Utility::PathUtility } }

    it 'joins array elements with slashes' do
      result = utility.join_path_parts(%w[users 123 posts])
      expect(result).to eq('/users/123/posts')
    end

    it 'handles empty array' do
      result = utility.join_path_parts([])
      expect(result).to eq('/')
    end

    it 'handles array with single element' do
      result = utility.join_path_parts(['users'])
      expect(result).to eq('/users')
    end

    it 'handles elements with special characters' do
      result = utility.join_path_parts(['user files', 'report.pdf'])
      expect(result).to eq('/user files/report.pdf')
    end
  end

  describe 'validation caching' do
    let(:route) { RubyRoutes::Route.new('/users/:id', to: 'users#show') }

    it 'caches validation results for frozen params' do
      # Create a frozen params hash
      params = { id: '123' }.freeze
      result = double('validation_result')

      # Check that result is not cached initially
      initial_cached_result = route.send(:get_cached_validation, params)
      expect(initial_cached_result).to be_nil

      # Cache a result
      route.send(:cache_validation_result, params, result)

      # Verify it was cached
      cached_result = route.send(:get_cached_validation, params)
      expect(cached_result).to eq(result)
    end

    it "doesn't cache validation results for non-frozen params" do
      # Create a non-frozen params hash
      params = { id: '123' }
      result = double('validation_result')

      # Cache a result
      route.send(:cache_validation_result, params, result)

      # Verify it wasn't cached
      cached_result = route.send(:get_cached_validation, params)
      expect(cached_result).to be_nil
    end

    it 'returns nil for get_cached_validation when validation cache is nil' do
      # Force nil validation cache
      route.instance_variable_set(:@validation_cache, nil)

      params = { id: '123' }.freeze
      result = route.send(:get_cached_validation, params)
      expect(result).to be_nil
    end

    it 'normalizes leading slash for paths without slashes' do
      router.scope path: 'api' do
        get 'v1/users', to: 'users#index'
      end
      route = router.route_set.routes.first
      expect(route.path).to eq('/api/v1/users')  # Ensure leading /
    end
  end

  describe 'immutability after finalization' do
    let(:finalized_router) { RubyRoutes::Router.new { get '/test', to: 'test#index' }.finalize! }

    it 'prevents adding routes after finalization' do
      expect { finalized_router.get '/new', to: 'new#index' }.to raise_error(RuntimeError, 'Router finalized (immutable)')
    end

    it 'prevents defining resources after finalization' do
      expect { finalized_router.resources :users }.to raise_error(RuntimeError, 'Router finalized (immutable)')
    end

    it 'prevents defining root route after finalization' do
      expect { finalized_router.root }.to raise_error(RuntimeError, 'Router finalized (immutable)')
    end

    it 'prevents defining namespace after finalization' do
      expect { finalized_router.namespace :admin }.to raise_error(RuntimeError, 'Router finalized (immutable)')
    end

    it 'prevents defining scope after finalization' do
      expect { finalized_router.scope path: '/api' }.to raise_error(RuntimeError, 'Router finalized (immutable)')
    end

    it 'prevents defining constraints after finalization' do
      expect { finalized_router.constraints id: /\d+/ }.to raise_error(RuntimeError, 'Router finalized (immutable)')
    end

    it 'prevents defining defaults after finalization' do
      expect { finalized_router.defaults format: :json }.to raise_error(RuntimeError, 'Router finalized (immutable)')
    end

    it 'prevents defining concerns after finalization' do
      expect { finalized_router.concern :testable }.to raise_error(RuntimeError, 'Router finalized (immutable)')
    end

    it 'prevents using concerns after finalization' do
      finalized_router = RubyRoutes::Router.new do
        concern :testable do
          get '/test', to: 'test#index'
        end
      end.finalize!

      expect { finalized_router.concerns :testable }.to raise_error(RuntimeError, 'Router finalized (immutable)')
    end

    it 'prevents mounting after finalization' do
      expect { finalized_router.mount(double('app')) }.to raise_error(RuntimeError, 'Router finalized (immutable)')
    end
  end
end
