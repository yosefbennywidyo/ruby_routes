# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Security Features' do
  describe 'Constraint Validation Security' do
    it 'defines ConstraintViolation exception' do
      expect(RubyRoutes::ConstraintViolation).to be < RubyRoutes::Error
    end

    it 'validates empty string values against constraints' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', constraints: { id: :int })

      # Simulate empty string parameter
      params = { 'id' => '' }
      expect do
        route.send(:validate_constraints_fast!, params)
      end.to raise_error(RubyRoutes::ConstraintViolation)
    end

    it 'validates nil values against constraints' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', constraints: { id: :int })

      # Simulate nil parameter
      params = { 'id' => nil }
      expect do
        route.send(:validate_constraints_fast!, params)
      end.to raise_error(RubyRoutes::ConstraintViolation)
    end

    it 'protects against ReDoS attacks with regex constraints' do
      # Malicious regex that causes exponential backtracking
      evil_regex = /(a+)+b/
      route = RubyRoutes::RadixTree.new('/test/:param', to: 'test#show', constraints: { param: evil_regex })

      # Input that would cause catastrophic backtracking
      malicious_input = "#{'a' * 30}X"

      start_time = Time.now
      expect do
        route.extract_params("/test/#{malicious_input}")
      end.to raise_error(RubyRoutes::ConstraintViolation)

      # Should complete quickly due to timeout protection
      expect(Time.now - start_time).to be < 0.5
    end

    it 'protects against slow Proc constraints' do
      slow_proc = lambda { |_value|
        # CPU-intensive operation that can be interrupted
        start_time = Time.now
        while Time.now - start_time < 1
          # Busy loop
        end
        true
      }

      route = RubyRoutes::RadixTree.new('/test/:param', to: 'test#show', constraints: { param: slow_proc })

      expect do
        route.extract_params('/test/anything')
      end.to raise_error(RubyRoutes::ConstraintViolation, /timed out/)
    end

    it 'validates UUID constraints properly' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', constraints: { id: :uuid })

      # Valid UUID should pass
      valid_uuid = '550e8400-e29b-41d4-a716-446655440000'
      result = route.extract_params("/users/#{valid_uuid}")
      expect(result['id']).to eq(valid_uuid)

      # Invalid UUID should fail
      expect do
        route.extract_params('/users/not-a-uuid')
      end.to raise_error(RubyRoutes::ConstraintViolation)
    end

    it 'validates integer constraints properly' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', constraints: { id: :int })

      # Valid integer should pass
      result = route.extract_params('/users/123')
      expect(result['id']).to eq('123')

      # Invalid integer should fail
      expect do
        route.extract_params('/users/abc')
      end.to raise_error(RubyRoutes::ConstraintViolation)
    end

    it 'validates email constraints' do
      route = RubyRoutes::RadixTree.new('/users/:email', to: 'users#show', constraints: { email: :email })

      # Valid email should pass
      result = route.extract_params('/users/test@example.com')
      expect(result['email']).to eq('test@example.com')

      # Invalid email should fail
      expect do
        route.extract_params('/users/invalid-email')
      end.to raise_error(RubyRoutes::ConstraintViolation)
    end

    it 'validates slug constraints' do
      route = RubyRoutes::RadixTree.new('/posts/:slug', to: 'posts#show', constraints: { slug: :slug })

      # Valid slug should pass
      result = route.extract_params('/posts/my-awesome-post')
      expect(result['slug']).to eq('my-awesome-post')

      # Invalid slug should fail
      expect do
        route.extract_params('/posts/My_Invalid Slug!')
      end.to raise_error(RubyRoutes::ConstraintViolation)
    end

    it 'validates alpha constraints' do
      route = RubyRoutes::RadixTree.new('/categories/:name', to: 'categories#show', constraints: { name: :alpha })

      # Valid alpha should pass
      result = route.extract_params('/categories/Technology')
      expect(result['name']).to eq('Technology')

      # Invalid alpha should fail
      expect do
        route.extract_params('/categories/Tech123')
      end.to raise_error(RubyRoutes::ConstraintViolation)
    end

    it 'validates alphanumeric constraints' do
      route = RubyRoutes::RadixTree.new('/codes/:code', to: 'codes#show', constraints: { code: :alphanumeric })

      # Valid alphanumeric should pass
      result = route.extract_params('/codes/ABC123')
      expect(result['code']).to eq('ABC123')

      # Invalid alphanumeric should fail
      expect do
        route.extract_params('/codes/ABC-123')
      end.to raise_error(RubyRoutes::ConstraintViolation)
    end

    it 'validates hash constraints with length limits' do
      route = RubyRoutes::RadixTree.new('/users/:username', to: 'users#show',
                                                            constraints: { username: { min_length: 3, max_length: 20 } })

      # Valid length should pass
      result = route.extract_params('/users/john')
      expect(result['username']).to eq('john')

      # Too short should fail
      expect do
        route.extract_params('/users/jo')
      end.to raise_error(RubyRoutes::ConstraintViolation, /too short/)

      # Too long should fail
      expect do
        route.extract_params("/users/#{'a' * 25}")
      end.to raise_error(RubyRoutes::ConstraintViolation, /too long/)
    end

    it 'validates hash constraints with allowed values' do
      route = RubyRoutes::RadixTree.new('/posts/:status', to: 'posts#show',
                                                          constraints: { status: { in: %w[draft published archived] } })

      # Allowed value should pass
      result = route.extract_params('/posts/published')
      expect(result['status']).to eq('published')

      # Disallowed value should fail
      expect do
        route.extract_params('/posts/invalid')
      end.to raise_error(RubyRoutes::ConstraintViolation, /not in allowed list/)
    end

    it 'validates hash constraints with forbidden values' do
      route = RubyRoutes::RadixTree.new('/users/:username', to: 'users#show',
                                                            constraints: { username: { not_in: %w[admin root system] } })

      # Allowed value should pass
      result = route.extract_params('/users/john')
      expect(result['username']).to eq('john')

      # Forbidden value should fail
      expect do
        route.extract_params('/users/admin')
      end.to raise_error(RubyRoutes::ConstraintViolation, /in forbidden list/)
    end

    it 'validates hash constraints with numeric ranges' do
      route = RubyRoutes::RadixTree.new('/products/:price', to: 'products#show',
                                                            constraints: { price: { range: 1..1000 } })

      # Value in range should pass
      result = route.extract_params('/products/50')
      expect(result['price']).to eq('50')

      # Value out of range should fail
      expect do
        route.extract_params('/products/2000')
      end.to raise_error(RubyRoutes::ConstraintViolation, /not in allowed range/)
    end

    it 'shows deprecation warning for Proc constraints' do
      constraint_proc = ->(value) { value.to_i > 100 }
      route = RubyRoutes::RadixTree.new('/test/:param', to: 'test#show', constraints: { param: constraint_proc })

      expect do
        route.extract_params('/test/150')
      end.to output(/DEPRECATION.*Proc constraints are deprecated/).to_stderr
    end

    it 'only shows deprecation warning once per parameter' do
      constraint_proc = ->(value) { value.to_i > 100 }
      route = RubyRoutes::RadixTree.new('/test/:param', to: 'test#show', constraints: { param: constraint_proc })

      # First call should show warning
      expect do
        route.extract_params('/test/150')
      end.to output(/DEPRECATION/).to_stderr

      # Second call should not show warning
      expect do
        route.extract_params('/test/200')
      end.not_to output(/DEPRECATION/).to_stderr
    end
  end

  describe 'Thread Safety' do
    it 'handles concurrent cache key generation safely' do
      route_set = RubyRoutes::RouteSet.new
      route_set.add_route(RubyRoutes::RadixTree.new('/test', to: 'test#index'))

      threads = []
      mutex = Mutex.new
      results = []

      10.times do |thread_id|
        threads << Thread.new do
          thread_results = []
          100.times do |i|
            key = route_set.send(:cache_key_for_request, 'GET', "/test#{thread_id}_#{i}")
            thread_results << key
          end
          mutex.synchronize { results.concat(thread_results) }
        end
      end

      threads.each(&:join)

      # Should have 1000 unique cache keys
      expect(results.uniq.size).to eq(1000)
    end

    it 'handles concurrent params pool access safely' do
      route_set = RubyRoutes::RouteSet.new

      threads = []

      10.times do
        threads << Thread.new do
          100.times do
            params = route_set.send(:thread_local_params)
            params[:test] = Thread.current.object_id
            route_set.send(:return_params_to_pool, params)
          end
        end
      end

      threads.each(&:join)

      # Should complete without errors
      expect(true).to be true
    end
  end
end
