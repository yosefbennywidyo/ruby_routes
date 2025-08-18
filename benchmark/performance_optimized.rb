#!/usr/bin/env ruby

require 'benchmark'
require 'memory_profiler'
require_relative '../lib/ruby_routes'

# Create a router with many routes for realistic testing
router = RubyRoutes.draw do
  # Basic routes
  get '/', to: 'home#index'
  get '/about', to: 'pages#about'
  get '/contact', to: 'pages#contact'

  # RESTful resources with explicit names
  get '/users', as: :users, to: 'users#index'
  get '/users/:id', as: :user, to: 'users#show'
  get '/users/:id/edit', as: :edit_user, to: 'users#edit'
  
  resources :posts
  resources :comments
  resources :categories
  resources :tags

  # Nested resources
  resources :users do
    resources :posts
    resources :comments
  end

  # Admin namespace
  namespace :admin do
    resources :users
    resources :posts
    resources :categories
    resources :settings
  end

  # API namespace with versioning
  namespace :api do
    namespace :v1 do
      resources :users
      resources :posts
    end
    namespace :v2 do
      resources :users
      resources :posts
    end
  end

  # Complex routes with constraints
  get '/products/:id', to: 'products#show', constraints: { id: :int }
  get '/users/:email', to: 'users#show_by_email', constraints: { email: :email }
  get '/posts/:slug', to: 'posts#show', constraints: { slug: :slug }
end

puts "Router created with #{router.route_set.instance_variable_get(:@routes).size} routes"

# Test paths for benchmarking
test_paths = [
  ['GET', '/'],
  ['GET', '/users'],
  ['GET', '/users/123'],
  ['POST', '/users'],
  ['GET', '/users/123/posts'],
  ['GET', '/admin/users'],
  ['GET', '/api/v1/users'],
  ['GET', '/api/v2/posts/456'],
  ['GET', '/products/789'],
  ['GET', '/users/test@example.com'],
  ['GET', '/posts/my-awesome-post']
]

# Warm up the cache
puts "\nWarming up cache..."
test_paths.each do |method, path|
  router.route_set.match(method, path)
end

puts "\nBenchmarking route matching (optimized):"
puts "=" * 50

# Route matching benchmark
Benchmark.bm(20) do |x|
  x.report("Route matching:") do
    10_000.times do
      test_paths.each do |method, path|
        router.route_set.match(method, path)
      end
    end
  end
end

puts "\nBenchmarking path generation (optimized):"
puts "=" * 50

# Path generation benchmark
Benchmark.bm(20) do |x|
  x.report("Path generation:") do
    10_000.times do
      router.route_set.generate_path(:user, id: '123')
      router.route_set.generate_path(:users)
      router.route_set.generate_path(:edit_user, id: '456')
    end
  end
end

# Memory profiling
puts "\nMemory usage analysis:"
puts "=" * 50

memory_before = `ps -o rss= -p #{Process.pid}`.to_i
puts "Memory before: #{memory_before} KB"

# Run operations
1000.times do
  test_paths.each do |method, path|
    router.route_set.match(method, path)
  end
  
  router.route_set.generate_path(:user, id: '123')
  router.route_set.generate_path(:users)
end

memory_after = `ps -o rss= -p #{Process.pid}`.to_i
puts "Memory after: #{memory_after} KB"
puts "Memory increase: #{memory_after - memory_before} KB"

# Cache statistics
puts "\nCache performance:"
puts "=" * 50
stats = router.route_set.cache_stats
puts "Cache hits: #{stats[:hits]}"
puts "Cache misses: #{stats[:misses]}"
puts "Hit rate: #{stats[:hit_rate]}"
puts "Cache size: #{stats[:size]}"

puts "\nPerformance test completed!"
