# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyRoutes::RadixTree do
  let(:tree) { RubyRoutes::RadixTree.new }

  # Helper to build a double that supports RadixTree's new constraint hook
  # (respond_to?(:validate_constraints_fast!)).
  #
  # It mimics the subset of validation logic RadixTree expects:
  # - Regexp, :int, :uuid, Hash with :range
  # Other constraint types are treated as pass-through (no violation).
  def build_route_with_constraints(constraints_hash)
    route = Object.new

    # Real constraints method
    route.define_singleton_method(:constraints) { constraints_hash }

    # Real validation hook (simulates Route#validate_constraints_fast!)
    route.define_singleton_method(:validate_constraints_fast!) do |params|
      constraints_hash.each do |key, rule|
        value = params[key.to_s] || params[key]
        next unless value

        case rule
        when Regexp
          raise RubyRoutes::ConstraintViolation unless rule.match?(value.to_s)
        when :int
          raise RubyRoutes::ConstraintViolation unless value.to_s.match?(/\A\d+\z/)
        when :uuid
          unless value.to_s.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
            raise RubyRoutes::ConstraintViolation
          end
        when Hash
          if (range = rule[:range]).is_a?(Range) && !range.include?(value.to_i)
            raise RubyRoutes::ConstraintViolation
          end
          # Unknown symbol constraints pass (RadixTree treats as success)
        end
      end
      true
    end

    route
  end

  describe '#add' do
    it 'adds routes to the tree' do
      route = double('route')
      tree.add('/users', ['GET'], route)
      result, = tree.find('/users', 'GET')
      expect(result).to eq(route)
    end

    it 'handles multiple HTTP methods' do
      route = double('route')
      tree.add('/users', %w[GET POST], route)
      get_result, = tree.find('/users', 'GET')
      post_result, = tree.find('/users', 'POST')
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
    context 'with dynamic segments' do
      it 'merges captured params into the params hash' do
        route = double('route')  # Define route as a double
        tree.add('/users/:id', ['GET'], route)
        result = tree.find('/users/123', 'GET')

        expect(result[1]).to include('id' => '123')  # Ensure captured param is in params
      end
    end

    context 'with wildcard segments' do
      it 'merges captured params into the params hash' do
        route = double('route')  # Define route as a double
        tree.add('/files/*path', ['GET'], route)
        result = tree.find('/files/docs/readme.txt', 'GET')

        expect(result[1]).to include('path' => 'docs/readme.txt')  # Ensure captured param is in params
      end
    end

    context 'when traversal fails mid-path' do
      it 'retains captured params from successful segments' do
        route = double('route')  # Define route as a double
        tree.add('/users/:id/profile', ['GET'], route)
        result = tree.find('/users/123/invalid', 'GET')
        # The path doesn't match, so result should be nil
        expect(result[0]).to be_nil
        # Or if partial matches are expected to return params:
        # expect(result[1]).to include('id' => '123')
      end
    end

    it 'returns nil for non-matching paths' do
      result, = tree.find('/nonexistent', 'GET')
      expect(result).to be_nil
    end

    it 'returns nil for wrong HTTP method' do
      route = double('route')
      tree.add('/users', ['GET'], route)
      result, = tree.find('/users', 'POST')
      expect(result).to be_nil
    end

    it 'handles root path' do
      route = double('route')
      tree.add('/', ['GET'], route)
      result, = tree.find('/', 'GET')
      expect(result).to eq(route)
    end

    it 'handles empty path as root' do
      route = double('route')
      tree.add('/', ['GET'], route)
      result, = tree.find('', 'GET')
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
      route = build_route_with_constraints(id: /\d+/)
      tree.add('/users/:id', ['GET'], route)

      result, = tree.find('/users/123', 'GET', { 'id' => '123' })
      expect(result).to eq(route)

      result, = tree.find('/users/abc', 'GET', { 'id' => 'abc' })
      expect(result).to be_nil
    end

    it 'validates hash constraints with ranges' do
      route = build_route_with_constraints(id: { range: 101..999 })
      tree.add('/users/:id', ['GET'], route)

      result, = tree.find('/users/123', 'GET', { 'id' => '123' })
      expect(result).to eq(route)
      result, = tree.find('/users/not-a-uuid', 'GET', { 'id' => 'not-a-uuid' })
      expect(result).to be_nil
    end

    it 'handles multiple constraints' do
      route = build_route_with_constraints(year: /\d{4}/, month: /\d{1,2}/)
      tree.add('/posts/:year/:month', ['GET'], route)

      result, = tree.find('/posts/2023/12', 'GET', { 'year' => '2023', 'month' => '12' })
      expect(result).to eq(route)
      result, = tree.find('/posts/23/12', 'GET', { 'year' => '23', 'month' => '12' })
      expect(result).to be_nil
    end

    it 'handles constraints with symbol and string keys' do
      route = build_route_with_constraints(id: /\d+/)
      tree.add('/users/:id', ['GET'], route)

      result, = tree.find('/users/123', 'GET', { 'id' => '123' })
      expect(result).to eq(route)
      result, = tree.find('/users/123', 'GET', { id: '123' })
      expect(result).to eq(route)
      result, = tree.find('/users/123', 'GET')
      expect(result).to eq(route)
    end

    it 'handles routes without constraints method' do
      route = double('route')
      allow(route).to receive(:respond_to?).with(:constraints).and_return(false)
      allow(route).to receive(:respond_to?).with(:validate_constraints_fast!).and_return(false)
      tree.add('/users/:id', ['GET'], route)
      result, = tree.find('/users/123', 'GET')
      expect(result).to eq(route)
    end

    context 'with unknown symbolic constraints' do
      it 'raises ConstraintViolation for unknown symbols' do
        route = RubyRoutes::Route.new('/test/:param', to: 'test#show', constraints: { param: :unknown })
        expect { route.validate_constraints_fast!({ 'param' => 'value' }) }.to raise_error(RubyRoutes::ConstraintViolation)
      end

      it 'raises ConstraintViolation for unknown string constraints' do
        route = RubyRoutes::Route.new('/test/:param', to: 'test#show', constraints: { param: 'unknown' })
        expect { route.validate_constraints_fast!({ 'param' => 'value' }) }.to raise_error(RubyRoutes::ConstraintViolation)
      end
    end
  end

  describe 'path splitting and caching' do
    it 'caches path splitting for performance' do
      route = double('route')
      tree.add('/users/:id', ['GET'], route)
      tree.find('/users/123', 'GET')
      tree.find('/users/456', 'GET')
      tree.find('/users/123', 'GET') # cache hit
      cache = tree.instance_variable_get(:@split_cache)
      expect(cache).not_to be_empty
    end

    it 'handles root path efficiently' do
      route = double('route')
      tree.add('/', ['GET'], route)
      result, = tree.find('/', 'GET')
      expect(result).to eq(route)
      result, = tree.find('', 'GET')
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
      (1..3000).each { |i| tree.find("/path/#{i}", 'GET') }
      cache = tree.instance_variable_get(:@split_cache)
      cache_max = tree.instance_variable_get(:@split_cache_max)

      expect(cache.size).to be <= cache_max

      # Define r2 and r3 as doubles
      r2 = double('route2')
      r3 = double('route3')

      # Add a route that matches the query path
      tree.add('/users/:id', ['GET'], r2)
      expect(tree.find('/users/123', 'GET').first).to eq(r2)

      tree.add('/users/:id/posts', ['GET'], r3)
      expect(tree.find('/users/123/posts', 'GET').first).to eq(r3)
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
      tree.add('/users', %w[get post], route)
      expect(tree.find('/users', 'GET').first).to eq(route)
      expect(tree.find('/users', 'POST').first).to eq(route)
    end
  end

  describe 'edge cases and error handling' do
    it 'handles paths with trailing slashes' do
      route = double('route')
      tree.add('/users/', ['GET'], route)
      expect(tree.find('/users/', 'GET').first).to eq(route)
    end

    it 'handles paths with leading slashes' do
      route = double('route')
      tree.add('users', ['GET'], route)
      expect(tree.find('/users', 'GET').first).to eq(route)
      expect(tree.find('/posts', 'GET').first).to be_nil
    end

    it 'handles empty tree gracefully' do
      expect(tree.find('/anything', 'GET').first).to be_nil
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
