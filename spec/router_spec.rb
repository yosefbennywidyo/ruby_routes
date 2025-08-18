require 'spec_helper'

RSpec.describe RubyRoutes do
  describe '.new' do
    it 'creates a new router instance' do
      router = RubyRoutes.new
      expect(router).to be_a(RubyRoutes::Router)
    end

    it 'accepts a block for route definition' do
      router = RubyRoutes.new do
        get '/', to: 'home#index'
      end

      expect(router.route_set.routes.size).to eq(1)
      expect(router.route_set.routes.first.path).to eq('/')
    end
  end

  describe '.draw' do
    it 'creates a router and yields to block' do
      router = RubyRoutes.draw do
        get '/about', to: 'pages#about'
      end

      expect(router.route_set.routes.size).to eq(1)
      expect(router.route_set.routes.first.path).to eq('/about')
    end
  end
end

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

      expect(routes.size).to eq(8)

      # Collection routes
      expect(routes.any? { |r| r.path == '/users' && r.action == 'index' }).to be true
      expect(routes.any? { |r| r.path == '/users/new' && r.action == 'new' }).to be true
      expect(routes.any? { |r| r.path == '/users' && r.action == 'create' && r.methods.include?('POST') }).to be true

      # Member routes
      expect(routes.any? { |r| r.path == '/users/:id' && r.action == 'show' }).to be true
      expect(routes.any? { |r| r.path == '/users/:id/edit' && r.action == 'edit' }).to be true
      expect(routes.any? { |r| r.path == '/users/:id' && r.action == 'update' && r.methods.include?('PUT') }).to be true
      expect(routes.any? { |r| r.path == '/users/:id' && r.action == 'update' && r.methods.include?('PATCH') }).to be true
      expect(routes.any? { |r| r.path == '/users/:id' && r.action == 'destroy' }).to be true
    end

    it 'defines nested resources routes correctly' do
      router.resources :posts, nested: :comments
      routes = router.route_set.routes

      # Verify nested resource routes exist
      expect(routes.any? { |r| r.path == '/posts/:id/comments' && r.action == 'index' }).to be true
      expect(routes.any? { |r| r.path == '/posts/:id/comments/new' && r.action == 'new' }).to be true
      expect(routes.any? { |r| r.path == '/posts/:id/comments' && r.action == 'create' && r.methods.include?('POST') }).to be true
      expect(routes.any? { |r| r.path == '/posts/:id/comments/:nested_id' && r.action == 'show' }).to be true
      expect(routes.any? { |r| r.path == '/posts/:id/comments/:nested_id/edit' && r.action == 'edit' }).to be true
      expect(routes.any? { |r| r.path == '/posts/:id/comments/:nested_id' && r.action == 'update' && r.methods.include?('PUT') }).to be true
      expect(routes.any? { |r| r.path == '/posts/:id/comments/:nested_id' && r.action == 'update' && r.methods.include?('PATCH') }).to be true
      
      # Critical test: DELETE should only map to destroy action, not update
      delete_routes = routes.select { |r| r.path == '/posts/:id/comments/:nested_id' && r.methods.include?('DELETE') }
      expect(delete_routes.size).to eq(1)
      expect(delete_routes.first.action).to eq('destroy')
      
      # Ensure no DELETE route maps to update action
      expect(routes.any? { |r| r.path == '/posts/:id/comments/:nested_id' && r.action == 'update' && r.methods.include?('DELETE') }).to be false
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
  end
end
