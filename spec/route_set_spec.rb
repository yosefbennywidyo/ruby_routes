require 'spec_helper'

RSpec.describe RubyRoutes::RouteSet do
  let(:route_set) { RubyRoutes::RouteSet.new }

  describe '#add_route' do
    it 'adds a route to the collection' do
      route = RubyRoutes::RadixTree.new('/users', to: 'users#index')
      route_set.add_route(route)

      expect(route_set.routes).to include(route)
      expect(route_set.size).to eq(1)
    end

    it 'adds named routes to named_routes hash' do
      route = RubyRoutes::RadixTree.new('/users', as: :users, to: 'users#index')
      route_set.add_route(route)

      expect(route_set.find_named_route(:users)).to eq(route)
    end
  end

  describe '#find_route' do
    it 'finds a matching route' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show')
      route_set.add_route(route)

      found = route_set.find_route('GET', '/users/123')
      expect(found).to eq(route)
    end

    it 'returns nil for non-matching route' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show')
      route_set.add_route(route)

      found = route_set.find_route('GET', '/users')
      expect(found).to be_nil
    end

    it 'returns nil for wrong HTTP method' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show')
      route_set.add_route(route)

      found = route_set.find_route('POST', '/users/123')
      expect(found).to be_nil
    end
  end

  describe '#find_named_route' do
    it 'finds a named route' do
      route = RubyRoutes::RadixTree.new('/users', as: :users, to: 'users#index')
      route_set.add_route(route)

      found = route_set.find_named_route(:users)
      expect(found).to eq(route)
    end

    it 'raises error for non-existent named route' do
      expect { route_set.find_named_route(:nonexistent) }.to raise_error(RubyRoutes::RouteNotFound)
    end
  end

  describe '#match' do
    it 'returns route info for matching request' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show')
      route_set.add_route(route)

      result = route_set.match('GET', '/users/123')

      expect(result[:route]).to eq(route)
      expect(result[:params]).to eq({ 'id' => '123' })
      expect(result[:controller]).to eq('users')
      expect(result[:action]).to eq('show')
    end

    it 'returns nil for non-matching request' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show')
      route_set.add_route(route)

      result = route_set.match('GET', '/users')
      expect(result).to be_nil
    end
  end

  describe '#recognize_path' do
    it 'recognizes path with default GET method' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show')
      route_set.add_route(route)

      result = route_set.recognize_path('/users/123')

      expect(result[:route]).to eq(route)
      expect(result[:params]).to eq({ 'id' => '123' })
    end

    it 'recognizes path with custom method' do
      route = RubyRoutes::RadixTree.new('/users/:id', via: :post, to: 'users#create')
      route_set.add_route(route)

      result = route_set.recognize_path('/users/123', :post)

      expect(result[:route]).to eq(route)
      expect(result[:params]).to eq({ 'id' => '123' })
    end
  end

  describe '#generate_path' do
    it 'generates path from named route' do
      route = RubyRoutes::RadixTree.new('/users/:id', as: :user, to: 'users#show')
      route_set.add_route(route)

      path = route_set.generate_path(:user, id: '123')
      expect(path).to eq('/users/123')
    end

    it 'raises error for non-existent named route' do
      expect { route_set.generate_path(:nonexistent, id: '123') }.to raise_error(RubyRoutes::RouteNotFound)
    end
  end

  describe '#generate_path_from_route' do
    it 'generates path from route with parameters' do
      route = RubyRoutes::RadixTree.new('/users/:id/posts/:post_id', to: 'posts#show')

      path = route_set.generate_path_from_route(route, id: '123', post_id: '456')
      expect(path).to eq('/users/123/posts/456')
    end

    it 'removes unused parameters' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show')

      path = route_set.generate_path_from_route(route, id: '123', extra: 'value')
      expect(path).to eq('/users/123')
    end

    it 'handles root path' do
      route = RubyRoutes::RadixTree.new('/', to: 'home#index')

      path = route_set.generate_path_from_route(route)
      expect(path).to eq('/')
    end
  end

  describe '#clear!' do
    it 'removes all routes and resets state' do
      route1 = RubyRoutes::RadixTree.new('/users', to: 'users#index')
      route2 = RubyRoutes::RadixTree.new('/posts', to: 'posts#index')

      route_set.add_route(route1)
      route_set.add_route(route2)

      # Trigger some cache activity
      route_set.match('GET', '/users')
      route_set.match('GET', '/posts')

      expect(route_set.size).to eq(2)
      expect(route_set.empty?).to be false

      route_set.clear!

      expect(route_set.size).to eq(0)
      expect(route_set.empty?).to be true
      
      # Verify caches are cleared
      stats = route_set.cache_stats
      expect(stats[:hits]).to eq(0)
      expect(stats[:misses]).to eq(0)
      expect(stats[:size]).to eq(0)
    end

    it 'handles clearing empty route set' do
      expect(route_set.empty?).to be true
      
      expect { route_set.clear! }.not_to raise_error
      
      expect(route_set.empty?).to be true
      expect(route_set.size).to eq(0)
    end
  end

  describe 'enumerable methods' do
    it 'iterates over routes' do
      route1 = RubyRoutes::RadixTree.new('/users', to: 'users#index')
      route2 = RubyRoutes::RadixTree.new('/posts', to: 'posts#index')

      route_set.add_route(route1)
      route_set.add_route(route2)

      routes = []
      route_set.each { |route| routes << route }

      expect(routes).to eq([route1, route2])
    end

    it 'checks if route is included' do
      route = RubyRoutes::RadixTree.new('/users', to: 'users#index')
      route_set.add_route(route)

      expect(route_set.include?(route)).to be true
    end
  end

  describe '#cache_stats' do
    it 'returns cache statistics' do
      stats = route_set.cache_stats
      
      expect(stats).to have_key(:hits)
      expect(stats).to have_key(:misses)
      expect(stats).to have_key(:hit_rate)
      expect(stats).to have_key(:size)
    end

    it 'tracks cache hits and misses' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show')
      route_set.add_route(route)
      
      # First match - cache miss
      route_set.match('GET', '/users/123')
      stats1 = route_set.cache_stats
      
      # Second match - cache hit
      route_set.match('GET', '/users/123')
      stats2 = route_set.cache_stats
      
      expect(stats2[:hits]).to be > stats1[:hits]
    end
  end

  describe 'caching behavior' do
    it 'caches route matches for performance' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show')
      route_set.add_route(route)
      
      # First call
      result1 = route_set.match('GET', '/users/123')
      
      # Second call should use cache
      result2 = route_set.match('GET', '/users/123')
      
      expect(result1).to eq(result2)
      expect(result1[:params]['id']).to eq('123')
    end

    it 'handles cache eviction when cache gets large' do
      # Register a dynamic route so matches are cached
      route_set.add_route(RubyRoutes::RadixTree.new('/path/:id', to: 'dummy#show'))

      # Many unique paths to grow and then evict entries
      (1..10_000).each do |i|
        route_set.match('GET', "/path/#{i}")
      end

      stats = route_set.cache_stats
      expect(stats[:size]).to be < 10_000
    end
  end

  describe 'constraint handling' do
    it 'handles routes with constraints' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', constraints: { id: /\d+/ })
      route_set.add_route(route)
      
      expect(route.constraints[:id]).to eq(/\d+/)
    end
  end
end
