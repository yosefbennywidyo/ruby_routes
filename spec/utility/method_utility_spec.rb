# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyRoutes::Utility::MethodUtility do
  let(:dummy_class) do
    Class.new do
      include RubyRoutes::Utility::MethodUtility
    end
  end

  let(:utility) { dummy_class.new }
  describe '#normalize_http_method' do
    around(:each) do |example|
      cache = RubyRoutes::Utility::MethodUtility::METHOD_CACHE
      # Save current cache state
      original_hash = cache.inspect_hash.dup
      original_hits = cache.hits
      original_misses = cache.misses
      original_evictions = cache.evictions

      begin
        # Clear cache by replacing internal hash (not ideal but necessary for testing)
        cache.instance_variable_set(:@hash, {})
        cache.instance_variable_set(:@hits, 0)
        cache.instance_variable_set(:@misses, 0)
        cache.instance_variable_set(:@evictions, 0)
        example.run
      ensure
        # Restore original cache state
        cache.instance_variable_set(:@hash, original_hash)
        cache.instance_variable_set(:@hits, original_hits)
        cache.instance_variable_set(:@misses, original_misses)
        cache.instance_variable_set(:@evictions, original_evictions)
      end
    end

    it 'demonstrates mutable string key not corrupt in METHOD_CACHE' do
      mutable_key = 'get'.dup # Create a mutable copy
      # First call to cache it
      utility.normalize_http_method(mutable_key)
      expect(RubyRoutes::Utility::MethodUtility::METHOD_CACHE.keys).to include(mutable_key)

      # Mutate the key
      mutable_key.upcase!

      # The key is still 'get' because it's duplicated
      expect(RubyRoutes::Utility::MethodUtility::METHOD_CACHE.keys).to include('get')
      # The key is not 'GET' because it's duplicated
      expect(RubyRoutes::Utility::MethodUtility::METHOD_CACHE.keys).not_to include('GET')
    end

    it "does not mutate METHOD_CACHE key when non-String input's to_s result is later mutated" do
      custom_object = Object.new
      mutable_key   = 'get'.dup
      allow(custom_object).to receive(:to_s).and_return(mutable_key)

      utility.normalize_http_method(custom_object)
      key_in_cache = RubyRoutes::Utility::MethodUtility::METHOD_CACHE.keys.find { |k| k == 'get' }
      expect(key_in_cache).not_to be(mutable_key)

      mutable_key.upcase!

      expect(RubyRoutes::Utility::MethodUtility::METHOD_CACHE.keys).to include('get')
      expect(RubyRoutes::Utility::MethodUtility::METHOD_CACHE.keys).not_to include('GET')
    end
  end
end
