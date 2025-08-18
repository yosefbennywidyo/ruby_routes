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
      expect {
        route.send(:validate_constraints_fast!, params)
      }.to raise_error(RubyRoutes::ConstraintViolation)
    end

    it 'validates nil values against constraints' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', constraints: { id: :int })
      
      # Simulate nil parameter
      params = { 'id' => nil }
      expect {
        route.send(:validate_constraints_fast!, params)
      }.to raise_error(RubyRoutes::ConstraintViolation)
    end

    it 'protects against ReDoS attacks with regex constraints' do
      # Malicious regex that causes exponential backtracking
      evil_regex = /(a+)+b/
      route = RubyRoutes::RadixTree.new('/test/:param', to: 'test#show', constraints: { param: evil_regex })
      
      # Input that would cause catastrophic backtracking
      malicious_input = 'a' * 30 + 'X'
      
      start_time = Time.now
      expect {
        route.extract_params("/test/#{malicious_input}")
      }.to raise_error(RubyRoutes::ConstraintViolation)
      
      # Should complete quickly due to timeout protection
      expect(Time.now - start_time).to be < 0.5
    end

    it 'protects against slow Proc constraints' do
      slow_proc = ->(value) { sleep(1); true }
      route = RubyRoutes::RadixTree.new('/test/:param', to: 'test#show', constraints: { param: slow_proc })
      
      expect {
        route.extract_params('/test/anything')
      }.to raise_error(RubyRoutes::ConstraintViolation, /timed out/)
    end

    it 'validates UUID constraints properly' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', constraints: { id: :uuid })
      
      # Valid UUID should pass
      valid_uuid = '550e8400-e29b-41d4-a716-446655440000'
      result = route.extract_params("/users/#{valid_uuid}")
      expect(result['id']).to eq(valid_uuid)
      
      # Invalid UUID should fail
      expect {
        route.extract_params('/users/not-a-uuid')
      }.to raise_error(RubyRoutes::ConstraintViolation)
    end

    it 'validates integer constraints properly' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', constraints: { id: :int })
      
      # Valid integer should pass
      result = route.extract_params('/users/123')
      expect(result['id']).to eq('123')
      
      # Invalid integer should fail
      expect {
        route.extract_params('/users/abc')
      }.to raise_error(RubyRoutes::ConstraintViolation)
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
            key = route_set.send(:build_cache_key, 'GET', "/test#{thread_id}_#{i}")
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
            params = route_set.send(:get_thread_local_params)
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
