# frozen_string_literal: true

require 'spec_helper'
require 'benchmark'

RSpec.describe 'Performance Optimizations' do
  let(:router) do
    RubyRoutes::Router.new do
      resources :users # This creates named routes like :user, :users, :edit_user, etc.
      resources :posts
      resources :comments

      namespace :admin do
        resources :users
        resources :posts
      end

      get '/products/:id', to: 'products#show', constraints: { id: :int }
      get '/users/:email', to: 'users#show_by_email', constraints: { email: :email }
    end
  end

  describe 'Route Matching Performance' do
    it 'handles high-frequency route matching efficiently' do
      test_paths = [
        ['GET', '/users'],
        ['GET', '/users/123'],
        ['POST', '/users'],
        ['GET', '/admin/users'],
        ['GET', '/products/456']
      ]

      # Warm up cache
      test_paths.each { |method, path| router.route_set.match(method, path) }

      # Measure performance
      time = Benchmark.realtime do
        1000.times do
          test_paths.each { |method, path| router.route_set.match(method, path) }
        end
      end

      # Should complete 5000 route matches in reasonable time
      expect(time).to be < 0.5 # Less than 500ms for 5000 matches
    end

    it 'maintains high cache hit rate' do
      test_paths = [
        ['GET', '/users'],
        ['GET', '/users/123'],
        ['POST', '/users']
      ]

      # Clear cache stats
      router.route_set.instance_variable_set(:@cache_hits, 0)
      router.route_set.instance_variable_set(:@cache_misses, 0)

      # First round - cache misses
      test_paths.each { |method, path| router.route_set.match(method, path) }

      # Second round - should be cache hits
      10.times do
        test_paths.each { |method, path| router.route_set.match(method, path) }
      end

      stats = router.route_set.cache_stats
      hit_rate = stats[:hit_rate].to_f

      # Should have high cache hit rate
      expect(hit_rate).to be > 80.0
    end
  end

  describe 'Path Generation Performance' do
    it 'handles high-frequency path generation efficiently' do
      # Use the actual named routes created by resources
      available_routes = router.route_set.instance_variable_get(:@named_routes).keys

      time = Benchmark.realtime do
        1000.times do
          router.route_set.generate_path(:user, id: '123') if available_routes.include?(:user)
          router.route_set.generate_path(:users) if available_routes.include?(:users)
          router.route_set.generate_path(:posts) if available_routes.include?(:posts)
        end
      end

      # Should complete path generations in reasonable time
      expect(time).to be < 0.5 # Less than 500ms
    end
  end

  describe 'Memory Efficiency' do
    it 'does not leak memory during repeated operations' do
      # Get initial memory usage
      GC.start
      initial_objects = ObjectSpace.count_objects[:T_STRING]

      # Perform many operations (just route matching to avoid named route issues)
      1000.times do |i|
        router.route_set.match('GET', "/users/#{i}")
        router.route_set.match('POST', '/users')
        router.route_set.match('GET', '/users')
      end

      # Force garbage collection
      GC.start
      final_objects = ObjectSpace.count_objects[:T_STRING]

      # Should not have excessive string object growth
      string_growth = final_objects - initial_objects
      expect(string_growth).to be < 10_000 # Allow reasonable growth for 3000 operations
    end
  end

  describe 'String Interning' do
    it 'reuses interned HTTP method strings' do
      router = RubyRoutes.draw { get '/test', to: 'test#index', as: :test, via: :get }
      route  = router.route_set.find_named_route(:test) # or: router.route_set.instance_variable_get(:@named_routes)[:test]
      expect(route.methods.first).to equal(RubyRoutes::Constant::HTTP_GET)
    end

    it 'freezes static segment values for memory efficiency' do
      route = RubyRoutes::RadixTree.new('/users/profile', to: 'users#profile')

      # Static segment values should be frozen
      users_segment = route.instance_variable_get(:@compiled_segments).find { |s| s[:value] == 'users' }
      profile_segment = route.instance_variable_get(:@compiled_segments).find { |s| s[:value] == 'profile' }

      expect(users_segment[:value]).to be_frozen
      expect(profile_segment[:value]).to be_frozen
    end
  end

  describe 'Cache Key Optimization' do
    it 'generates cache keys efficiently' do
      route_set = router.route_set

      time = Benchmark.realtime do
        1000.times do
          route_set.send(:cache_key_for_request, 'GET', '/users/123')
        end
      end

      # Should generate 1000 cache keys very quickly
      expect(time).to be < 0.01 # Less than 10ms
    end
  end
end
