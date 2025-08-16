#!/usr/bin/env ruby

require_relative '../lib/ruby_routes'

# Create a new router
router = Router.draw do
  # Basic routes
  get '/', to: 'home#index'
  get '/about', to: 'pages#about'
  get '/contact', to: 'pages#contact'

  # Named routes
  get '/users', as: :users, to: 'users#index'
  get '/users/:id', as: :user, to: 'users#show'
  post '/users', as: :create_user, to: 'users#create'
  put '/users/:id', as: :update_user, to: 'users#update'
  delete '/users/:id', as: :delete_user, to: 'users#destroy'

  # Resources (RESTful)
  resources :posts
  resources :comments

  # Nested resources
  resources :categories do
    resources :products
  end

  # Namespace
  namespace :admin do
    resources :users
    resources :posts
  end

  # Scope with constraints
  scope constraints: { id: /\d+/ } do
    get '/items/:id', to: 'items#show'
  end

  # Root route
  root to: 'home#index'
end

puts "Router created with #{router.route_set.size} routes"
puts

# Test route matching
puts "Testing route matching:"
puts "GET /users/123: #{router.route_set.match('GET', '/users/123') ? 'MATCH' : 'NO MATCH'}"
puts "POST /users: #{router.route_set.match('POST', '/users') ? 'MATCH' : 'NO MATCH'}"
puts "GET /posts/456: #{router.route_set.match('GET', '/posts/456') ? 'MATCH' : 'NO MATCH'}"
puts "GET /admin/users: #{router.route_set.match('GET', '/admin/users') ? 'MATCH' : 'NO MATCH'}"
puts

# Test path generation
puts "Testing path generation:"
begin
  puts "users_path: #{router.route_set.generate_path(:users)}"
  puts "user_path(123): #{router.route_set.generate_path(:user, id: '123')}"
  puts "create_user_path: #{router.route_set.generate_path(:create_user)}"
rescue RubyRoutes::RouteNotFound => e
  puts "Error: #{e.message}"
end
puts

# List all routes
puts "All routes:"
router.route_set.routes.each do |route|
  puts "#{route.methods.join(', ')} #{route.path} -> #{route.controller}##{route.action}"
end
