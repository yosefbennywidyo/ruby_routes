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

# Helper method to print object counts and differences
def print_object_counts(before_counts = nil)
  counts = ObjectSpace.count_objects
  if before_counts
    diff = {}
    counts.each do |key, value|
      diff[key] = value - before_counts[key]
    end
    puts "  Object count differences:"
    diff.sort_by { |k, v| -v.abs }.first(10).each do |key, value|
      puts "    #{key}: #{value > 0 ? '+' : ''}#{value}"
    end
  else
    puts "  Current object counts:"
    counts.sort_by { |k, v| -v }.first(10).each do |key, value|
      puts "    #{key}: #{value}"
    end
  end
  counts
end

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

# Object counts before route matching
puts "Object counts before route matching:"
before_route_matching = print_object_counts

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

# Object counts after route matching
puts "\nObject counts after route matching:"
print_object_counts(before_route_matching)

puts "\nBenchmarking path generation (optimized):"
puts "=" * 50

# Object counts before path generation
puts "Object counts before path generation:"
before_path_gen = print_object_counts

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

# Object counts after path generation
puts "\nObject counts after path generation:"
print_object_counts(before_path_gen)

# Memory profiling using secure Ruby methods
puts "\nMemory usage analysis:"
puts "=" * 50

# Object counts before memory test
puts "Object counts before memory test:"
before_memory_test = print_object_counts

# Use Ruby's built-in memory measurement instead of shell commands
def get_memory_usage_kb
  # Use /proc/self/status on Linux systems for secure memory reading
  if File.exist?('/proc/self/status')
    status_content = File.read('/proc/self/status')
    if match = status_content.match(/VmRSS:\s+(\d+)\s+kB/)
      return match[1].to_i
    end
  end

  # Fallback: Use Ruby's ObjectSpace for memory estimation
  GC.start  # Force garbage collection for accurate measurement
  ObjectSpace.count_objects.values.sum / 1024  # Rough KB estimate
rescue => e
  puts "Warning: Could not measure memory usage: #{e.message}"
  0
end

memory_before = get_memory_usage_kb
puts "Memory before: #{memory_before} KB"

# Run operations
1000.times do
  test_paths.each do |method, path|
    router.route_set.match(method, path)
  end

  router.route_set.generate_path(:user, id: '123')
  router.route_set.generate_path(:users)
end

memory_after = get_memory_usage_kb
puts "Memory after: #{memory_after} KB"
puts "Memory increase: #{memory_after - memory_before} KB"

# Object counts after memory test
puts "\nObject counts after memory test:"
print_object_counts(before_memory_test)

# Cache statistics
puts "\nCache performance:"
puts "=" * 50
stats = router.route_set.cache_stats
puts "Cache hits: #{stats[:hits]}"
puts "Cache misses: #{stats[:misses]}"
puts "Hit rate: #{stats[:hit_rate]}"
puts "Cache size: #{stats[:size]}"

puts "\nPerformance test completed!"
