require 'spec_helper'

RSpec.describe 'Error Handling and Edge Cases' do
  describe 'RubyRoutes exceptions' do
    it 'defines custom exception hierarchy' do
      expect(RubyRoutes::Error).to be < StandardError
      expect(RubyRoutes::RouteNotFound).to be < RubyRoutes::Error
      expect(RubyRoutes::InvalidRoute).to be < RubyRoutes::Error
    end

    it 'raises RouteNotFound for missing named routes' do
      route_set = RubyRoutes::RouteSet.new
      
      expect {
        route_set.find_named_route(:nonexistent)
      }.to raise_error(RubyRoutes::RouteNotFound, "No route named 'nonexistent'")
    end

    it 'raises RouteNotFound for missing path generation' do
      route_set = RubyRoutes::RouteSet.new
      
      expect {
        route_set.generate_path(:nonexistent)
      }.to raise_error(RubyRoutes::RouteNotFound, "No route named 'nonexistent'")
    end

    it 'raises InvalidRoute for routes without controller/action' do
      expect {
        RubyRoutes::RadixTree.new('/invalid', {})
      }.to raise_error(RubyRoutes::InvalidRoute)
    end
  end

  describe 'Router edge cases' do
    let(:router) { RubyRoutes::Router.new }

    it 'handles empty route definitions' do
      expect(router.route_set.routes).to be_empty
    end

    it 'handles multiple root routes' do
      router.root to: 'home#index'
      router.root to: 'pages#home'
      
      # Should have two root routes
      root_routes = router.route_set.routes.select { |r| r.path == '/' }
      expect(root_routes.size).to eq(2)
    end

    it 'handles resources with invalid names' do
      # Should not raise error, just create routes
      expect {
        router.resources :""
      }.not_to raise_error
    end

    it 'handles deeply nested scopes' do
      router.namespace :api do
        namespace :v1 do
          namespace :admin do
            resources :users
          end
        end
      end
      
      routes = router.route_set.routes
      expect(routes.any? { |r| r.path.include?('/api/v1/admin/users') }).to be true
    end

    it 'handles scope with empty options' do
      expect {
        router.scope({}) do
          get '/test', to: 'test#index'
        end
      }.not_to raise_error
    end
  end

  describe 'RouteSet edge cases' do
    let(:route_set) { RubyRoutes::RouteSet.new }

    it 'handles empty route set operations' do
      expect(route_set.size).to eq(0)
      expect(route_set.empty?).to be true
      expect(route_set.routes).to be_empty
    end

    it 'handles iteration over empty route set' do
      routes = []
      route_set.each { |route| routes << route }
      expect(routes).to be_empty
    end

    it 'handles cache operations on empty set' do
      stats = route_set.cache_stats
      expect(stats[:hits]).to eq(0)
      expect(stats[:misses]).to eq(0)
    end

    it 'handles clearing empty route set' do
      expect { route_set.clear! }.not_to raise_error
      expect(route_set.empty?).to be true
    end

    it 'handles matching with malformed paths' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show')
      route_set.add_route(route)
      
      # These should not crash
      expect(route_set.match('GET', '')).to be_nil
      expect(route_set.match('GET', '///')).to be_nil
      expect(route_set.match('', '/users/123')).to be_nil
    end

    it 'handles very long cache keys' do
      route = RubyRoutes::RadixTree.new('/test', to: 'test#index')
      route_set.add_route(route)
      
      long_path = '/test' + '?' + ('a=1&' * 1000)
      
      expect { route_set.match('GET', long_path) }.not_to raise_error
    end
  end

  describe 'Route edge cases' do
    it 'handles routes with special characters in path' do
      expect {
        RubyRoutes::RadixTree.new('/users-and-posts', to: 'users#index')
      }.not_to raise_error
    end

    it 'handles routes with dots in path' do
      route = RubyRoutes::RadixTree.new('/api/v1.0/users', to: 'users#index')
      expect(route.path).to eq('/api/v1.0/users')
    end

    it 'handles routes with unicode characters' do
      expect {
        RubyRoutes::RadixTree.new('/ユーザー', to: 'users#index')
      }.not_to raise_error
    end

    it 'handles parameter extraction' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show')
      params = route.extract_params('/users/123')
      
      expect(params['id']).to eq('123')
    end

    it 'raises error for nil required parameters' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', as: :user)
      
      expect {
        route.generate_path(id: nil)
      }.to raise_error(RubyRoutes::RouteNotFound, /Missing or nil params: id/)
    end

    it 'raises error for multiple nil required parameters' do
      route = RubyRoutes::RadixTree.new('/users/:user_id/posts/:id', to: 'posts#show', as: :user_post)
      
      expect {
        route.generate_path(user_id: '123', id: nil)
      }.to raise_error(RubyRoutes::RouteNotFound, /Missing or nil params: id/)
    end

    it 'allows nil for optional parameters' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', as: :user)
      
      # Optional parameters (not in path) can be nil
      expect {
        path = route.generate_path(id: '123', format: nil)
        expect(path).to eq('/users/123')
      }.not_to raise_error
    end

    it 'handles constraints with nil values' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', constraints: { id: /\d+/ })
      
      # Should not crash with nil parameter
      expect(route.match?('GET', '/users/')).to be false
    end
  end

  describe 'Node edge cases' do
    let(:node) { RubyRoutes::Node.new }

    it 'handles traversal with empty segments' do
      result = node.traverse_for('', 0, [''], {})
      expect(result).to be_an(Array)
    end

    it 'handles parameter name assignment' do
      node.param_name = 'test'
      expect(node.param_name).to eq('test')
      
      node.param_name = nil
      expect(node.param_name).to be_nil
    end

    it 'handles handler operations on empty node' do
      expect(node.get_handler('GET')).to be_nil
      expect(node.is_endpoint).to be false
    end
  end

  describe 'String extensions edge cases' do
    it 'handles regular strings' do
      expect('user'.singularize).to eq('user')
      expect('user'.pluralize).to eq('users')
    end

    it 'handles strings with special characters' do
      expect('user-name'.singularize).to eq('user-name')
    end
  end

  describe 'Memory and performance edge cases' do
    it 'handles large number of routes without memory issues' do
      router = RubyRoutes::Router.new
      
      # Add many routes
      100.times do |i|
        router.get "/path#{i}", to: "controller#{i}#action#{i}"
      end
      
      expect(router.route_set.size).to eq(100)
    end

    it 'handles deep parameter nesting' do
      route = RubyRoutes::RadixTree.new('/a/:a/b/:b/c/:c/d/:d/e/:e', to: 'test#show')
      params = route.extract_params('/a/1/b/2/c/3/d/4/e/5')
      
      expect(params['a']).to eq('1')
      expect(params['e']).to eq('5')
    end

    it 'handles concurrent access patterns' do
      route_set = RubyRoutes::RouteSet.new
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show')
      route_set.add_route(route)
      
      # Simulate concurrent access
      threads = 10.times.map do
        Thread.new do
          100.times { |i| route_set.match('GET', "/users/#{i}") }
        end
      end
      
      threads.each(&:join)
      
      # Should not crash and should have cache hits
      stats = route_set.cache_stats
      expect(stats[:hits]).to be > 0
    end
  end
end
