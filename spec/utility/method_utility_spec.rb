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
    it 'demonstrates mutable string key not corrupt in METHOD_CACHE' do
      mutable_key = 'get'.dup # Create a mutable copy
      # First call to cache it
      utility.normalize_http_method(mutable_key)
      expect(RubyRoutes::Utility::MethodUtility::METHOD_CACHE).to have_key(mutable_key)

      # Mutate the key
      mutable_key.upcase!

      # The key is still 'get' because it's duplicated
      expect(RubyRoutes::Utility::MethodUtility::METHOD_CACHE).to have_key('get')
      # The key is not 'GET' because it's duplicated
      expect(RubyRoutes::Utility::MethodUtility::METHOD_CACHE).not_to have_key('GET')
    end

    it "does not mutate METHOD_CACHE key when non-String input's to_s result is later mutated" do
      custom_object = Object.new
      mutable_key = 'get'.dup
      allow(custom_object).to receive(:to_s).and_return(mutable_key)

      utility.normalize_http_method(custom_object)
      key_in_cache = RubyRoutes::Utility::MethodUtility::METHOD_CACHE.keys.find { |k| k == 'get' }
      expect(key_in_cache).not_to be(mutable_key)

      mutable_key.upcase!

      expect(RubyRoutes::Utility::MethodUtility::METHOD_CACHE).to have_key('get')
      expect(RubyRoutes::Utility::MethodUtility::METHOD_CACHE).not_to have_key('GET')
    end
  end
end
