require 'spec_helper'

RSpec.describe RubyRoutes::RadixTree do
  let(:tree) { RubyRoutes::RadixTree.new }

  describe '#add' do
    it 'adds routes to the tree' do
      route = double('route')
      tree.add('/users', ['GET'], route)

      result, _ = tree.find('/users', 'GET')
      expect(result).to eq(route)
    end

    it 'handles multiple HTTP methods' do
      route = double('route')
      tree.add('/users', ['GET', 'POST'], route)

      get_result, _ = tree.find('/users', 'GET')
      post_result, _ = tree.find('/users', 'POST')

      expect(get_result).to eq(route)
      expect(post_result).to eq(route)
    end

    it 'handles dynamic segments' do
      route = double('route')
      tree.add('/users/:id', ['GET'], route)

      result, params = tree.find('/users/123', 'GET')
      expect(result).to eq(route)
      expect(params['id']).to eq('123')
    end

    it 'handles wildcard segments' do
      route = double('route')
      tree.add('/files/*path', ['GET'], route)

      result, params = tree.find('/files/docs/readme.txt', 'GET')
      expect(result).to eq(route)
      expect(params['path']).to eq('docs/readme.txt')
    end
  end

  describe '#find' do
    it 'returns nil for non-matching paths' do
      result, _ = tree.find('/nonexistent', 'GET')
      expect(result).to be_nil
    end

    it 'returns nil for wrong HTTP method' do
      route = double('route')
      tree.add('/users', ['GET'], route)

      result, _ = tree.find('/users', 'POST')
      expect(result).to be_nil
    end

    it 'handles root path' do
      route = double('route')
      tree.add('/', ['GET'], route)

      result, _ = tree.find('/', 'GET')
      expect(result).to eq(route)
    end

    it 'handles empty path as root' do
      route = double('route')
      tree.add('/', ['GET'], route)

      result, _ = tree.find('', 'GET')
      expect(result).to eq(route)
    end

    it 'extracts multiple parameters' do
      route = double('route')
      tree.add('/users/:user_id/posts/:id', ['GET'], route)

      result, params = tree.find('/users/123/posts/456', 'GET')
      expect(result).to eq(route)
      expect(params['user_id']).to eq('123')
      expect(params['id']).to eq('456')
    end
  end

  describe 'constraint handling' do
    it 'validates regex constraints' do
      route = double('route', constraints: { id: /\d+/ })
      allow(route).to receive(:respond_to?).with(:constraints).and_return(true)
      tree.add('/users/:id', ['GET'], route)

      # Should match numeric ID
      result, _ = tree.find('/users/123', 'GET', { 'id' => '123' })
      expect(result).to eq(route)

      # Should not match non-numeric ID
      result, _ = tree.find('/users/abc', 'GET', { 'id' => 'abc' })
      expect(result).to be_nil
    end

    it 'validates hash constraints with ranges' do
      # Hash constraints are validated at the Route level, not RadixTree level
      # This test verifies the route can be added and found
      route = double('route', constraints: { id: { range: 101..999 } })
      allow(route).to receive(:respond_to?).with(:constraints).and_return(true)
      allow(route).to receive(:respond_to?).with(:matches?).and_return(false)
      allow(route).to receive(:respond_to?).with(:i_respond_to_everything_so_im_not_really_a_matcher).and_return(false)
      tree.add('/users/:id', ['GET'], route)

      # Use values within the specified range
      result, _ = tree.find('/users/123', 'GET', { 'id' => '123' })
      expect(result).to eq(route)

      result, _ = tree.find('/users/500', 'GET', { 'id' => '500' })
      expect(result).to eq(route)

      # Value outside the range should return nil
      result, _ = tree.find('/users/50', 'GET', { 'id' => '50' })
      expect(result).to be_nil
    end

    it 'validates proc constraints (deprecated)' do
      # Proc constraint validation happens at Route level, not RadixTree level
      constraint_proc = ->(value) { value.to_i > 100 }
      route = double('route', constraints: { id: constraint_proc })
      allow(route).to receive(:respond_to?).with(:constraints).and_return(true)
      allow(route).to receive(:respond_to?).with(:i_respond_to_everything_so_im_not_really_a_matcher).and_return(false)
      tree.add('/users/:id', ['GET'], route)

      # RadixTree should find the route (deprecation warning happens in Route class)
      result, _ = tree.find('/users/123', 'GET', { 'id' => '123' })
      expect(result).to eq(route)
    end

    it 'validates integer constraints' do
      route = double('route', constraints: { id: :int })
      allow(route).to receive(:respond_to?).with(:constraints).and_return(true)
      tree.add('/users/:id', ['GET'], route)

      # Should match numeric string
      result, _ = tree.find('/users/123', 'GET', { 'id' => '123' })
      expect(result).to eq(route)

      # Should not match non-numeric string
      result, _ = tree.find('/users/abc', 'GET', { 'id' => 'abc' })
      expect(result).to be_nil
    end

    it 'validates UUID constraints' do
      route = double('route', constraints: { id: :uuid })
      allow(route).to receive(:respond_to?).with(:constraints).and_return(true)
      tree.add('/users/:id', ['GET'], route)

      uuid = '550e8400-e29b-41d4-a716-446655440000'

      # Should match valid UUID
      result, _ = tree.find("/users/#{uuid}", 'GET', { 'id' => uuid })
      expect(result).to eq(route)

      # Should not match invalid UUID
      result, _ = tree.find('/users/not-a-uuid', 'GET', { 'id' => 'not-a-uuid' })
      expect(result).to be_nil
    end

    it 'handles multiple constraints' do
      route = double('route', constraints: { year: /\d{4}/, month: /\d{1,2}/ })
      allow(route).to receive(:respond_to?).with(:constraints).and_return(true)
      tree.add('/posts/:year/:month', ['GET'], route)

      # Should match when all constraints pass
      result, _ = tree.find('/posts/2023/12', 'GET', { 'year' => '2023', 'month' => '12' })
      expect(result).to eq(route)

      # Should not match when one constraint fails
      result, _ = tree.find('/posts/23/12', 'GET', { 'year' => '23', 'month' => '12' })
      expect(result).to be_nil
    end

    it 'handles constraints with symbol and string keys' do
      route = double('route', constraints: { id: /\d+/ })
      allow(route).to receive(:respond_to?).with(:constraints).and_return(true)
      tree.add('/users/:id', ['GET'], route)

      # Test with string key in params
      result, _ = tree.find('/users/123', 'GET', { 'id' => '123' })
      expect(result).to eq(route)

      # Test with symbol key in params
      result, _ = tree.find('/users/123', 'GET', { id: '123' })
      expect(result).to eq(route)
    end

    it 'handles empty constraints' do
      route = double('route', constraints: {})
      allow(route).to receive(:respond_to?).with(:constraints).and_return(true)
      tree.add('/users/:id', ['GET'], route)

      result, _ = tree.find('/users/123', 'GET')
      expect(result).to eq(route)
    end

    it 'handles routes without constraints' do
      route = double('route')
      allow(route).to receive(:respond_to?).with(:constraints).and_return(false)
      tree.add('/users/:id', ['GET'], route)

      result, _ = tree.find('/users/123', 'GET')
      expect(result).to eq(route)
    end

    it 'handles unknown symbolic constraints gracefully' do
      route = double('route', constraints: { id: :unknown_constraint })
      allow(route).to receive(:respond_to?).with(:constraints).and_return(true)
      tree.add('/users/:id', ['GET'], route)

      # Should allow unknown symbolic constraints (treated as pass-through)
      result, _ = tree.find('/users/123', 'GET', { 'id' => '123' })
      expect(result).to eq(route)
    end
  end

  describe 'path splitting and caching' do
    it 'caches path splitting for performance' do
      route = double('route')
      tree.add('/users/:id', ['GET'], route)

      # Multiple calls with same path should use cache
      tree.find('/users/123', 'GET')
      tree.find('/users/456', 'GET')
      tree.find('/users/123', 'GET') # This should hit cache

      # Verify cache is working by checking internal state
      cache = tree.instance_variable_get(:@split_cache)
      expect(cache).not_to be_empty
    end

    it 'handles root path efficiently' do
      route = double('route')
      tree.add('/', ['GET'], route)

      result, _ = tree.find('/', 'GET')
      expect(result).to eq(route)

      # Empty path should also match root
      result, _ = tree.find('', 'GET')
      expect(result).to eq(route)
    end

    it 'handles complex paths with multiple segments' do
      route = double('route')
      tree.add('/api/v1/users/:id/posts/:post_id/comments', ['GET'], route)

      result, params = tree.find('/api/v1/users/123/posts/456/comments', 'GET')
      expect(result).to eq(route)
      expect(params['id']).to eq('123')
      expect(params['post_id']).to eq('456')
    end

    it 'evicts old cache entries when cache gets large' do
      route = double('route')
      tree.add('/path/:id', ['GET'], route)

      # Add many different paths to trigger cache eviction
      (1..3000).each do |i|
        tree.find("/path/#{i}", 'GET')
      end

      cache = tree.instance_variable_get(:@split_cache)
      cache_max = tree.instance_variable_get(:@split_cache_max)

      # Cache should not exceed max size
      expect(cache.size).to be <= cache_max
    end
  end

  describe 'performance optimizations' do
    it 'handles unrolled traversal for common path lengths' do
      route1 = double('route1')
      route2 = double('route2')
      route3 = double('route3')

      # Test 1 segment
      tree.add('/users', ['GET'], route1)
      result, _ = tree.find('/users', 'GET')
      expect(result).to eq(route1)

      # Test 2 segments
      tree.add('/users/:id', ['GET'], route2)
      result, _ = tree.find('/users/123', 'GET')
      expect(result).to eq(route2)

      # Test 3 segments
      tree.add('/users/:id/posts', ['GET'], route3)
      result, _ = tree.find('/users/123/posts', 'GET')
      expect(result).to eq(route3)
    end

    it 'handles longer paths with general traversal' do
      route = double('route')
      tree.add('/a/b/c/d/e/f/:id', ['GET'], route)

      result, params = tree.find('/a/b/c/d/e/f/123', 'GET')
      expect(result).to eq(route)
      expect(params['id']).to eq('123')
    end

    it 'normalizes HTTP methods during registration' do
      route = double('route')

      # Add with lowercase methods
      tree.add('/users', ['get', 'post'], route)

      # Should find with uppercase methods
      result, _ = tree.find('/users', 'GET')
      expect(result).to eq(route)

      result, _ = tree.find('/users', 'POST')
      expect(result).to eq(route)
    end
  end

  describe 'edge cases and error handling' do
    it 'handles paths with trailing slashes' do
      route = double('route')
      tree.add('/users/', ['GET'], route)

      result, _ = tree.find('/users/', 'GET')
      expect(result).to eq(route)
    end

    it 'handles paths with leading slashes' do
      route = double('route')
      tree.add('users', ['GET'], route) # No leading slash

      result, _ = tree.find('/users', 'GET')
      expect(result).to eq(route)
    end

    it 'returns nil for completely non-matching paths' do
      route = double('route')
      tree.add('/users', ['GET'], route)

      result, _ = tree.find('/posts', 'GET')
      expect(result).to be_nil
    end

    it 'handles empty tree gracefully' do
      result, _ = tree.find('/anything', 'GET')
      expect(result).to be_nil
    end

    it 'handles wildcard routes that consume remaining path' do
      route = double('route')
      tree.add('/files/*path', ['GET'], route)

      result, params = tree.find('/files/docs/readme.txt', 'GET')
      expect(result).to eq(route)
      expect(params['path']).to eq('docs/readme.txt')

      # Single file
      result, params = tree.find('/files/image.jpg', 'GET')
      expect(result).to eq(route)
      expect(params['path']).to eq('image.jpg')
    end
  end
end
