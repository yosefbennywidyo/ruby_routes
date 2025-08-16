#!/usr/bin/env ruby

require 'benchmark'
require_relative '../lib/ruby_routes'

# Create a router with many routes
router = RubyRoutes.draw do
  # Basic routes
  get '/', to: 'home#index'
  get '/about', to: 'pages#about'
  get '/contact', to: 'pages#contact'

  # User routes
  get '/users', as: :users, to: 'users#index'
  get '/users/new', as: :new_user, to: 'users#new'
  post '/users', as: :create_user, to: 'users#create'
  get '/users/:id', as: :user, to: 'users#show'
  get '/users/:id/edit', as: :edit_user, to: 'users#edit'
  put '/users/:id', as: :update_user, to: 'users#update'
  patch '/users/:id', as: :patch_user, to: 'users#update'
  delete '/users/:id', as: :delete_user, to: 'users#destroy'

  # Post routes
  resources :posts
  resources :comments

  # Admin routes
  namespace :admin do
    resources :users
    resources :posts
    resources :comments
  end

  # API routes
  namespace :api do
    resources :users
    resources :posts
    resources :comments
  end

  # Nested routes
  resources :categories do
    resources :products
  end

  # Custom routes
  get '/search', to: 'search#index'
  get '/search/:query', to: 'search#show'
  post '/search', to: 'search#create'

  # Root
  root to: 'home#index'
end

puts "Router created with #{router.route_set.size} routes"
puts

# Benchmark route matching
puts "Benchmarking route matching:"
puts "=" * 50

# Test cases
test_cases = [
  ['GET', '/'],
  ['GET', '/users'],
  ['GET', '/users/123'],
  ['POST', '/users'],
  ['PUT', '/users/123'],
  ['GET', '/admin/users'],
  ['GET', '/api/users/456'],
  ['GET', '/categories/1/products'],
  ['GET', '/search'],
  ['GET', '/search/query'],
  ['POST', '/search']
]

# Warm up
1000.times do
  test_cases.each do |method, path|
    router.route_set.match(method, path)
  end
end

# Benchmark
Benchmark.bm(20) do |bm|
  bm.report('Route matching:') do
    100_000.times do
      test_cases.each do |method, path|
        router.route_set.match(method, path)
      end
    end
  end
end

puts

# Benchmark path generation
puts "Benchmarking path generation:"
puts "=" * 50

named_routes = [:users, :user, :posts, :post, :admin_users, :api_users]

Benchmark.bm(20) do |bm|
  bm.report('Path generation:') do
    100_000.times do
      named_routes.each do |route_name|
        begin
          if route_name == :user
            router.route_set.generate_path(route_name, id: '123')
          elsif route_name == :post
            router.route_set.generate_path(route_name, id: '456')
          else
            router.route_set.generate_path(route_name)
          end
        rescue RubyRoutes::RouteNotFound
          # Some routes might not exist, that's okay for benchmark
        end
      end
    end
  end
end

puts

# Memory usage
puts "Memory usage information:"
puts "=" * 50

# Get memory usage before
memory_before = `ps -o rss= -p #{Process.pid}`.to_i

# Create some additional routes
100.times do |i|
  router.get "/test#{i}", to: "test#{i}#index"
end

# Get memory usage after
memory_after = `ps -o rss= -p #{Process.pid}`.to_i

puts "Memory before: #{memory_before} KB"
puts "Memory after: #{memory_after} KB"
puts "Memory increase: #{memory_after - memory_before} KB"
puts "Routes total: #{router.route_set.size}"

puts
puts "Performance test completed!"
