# frozen_string_literal: true

require 'spec_helper'

require_relative '../../lib/ruby_routes/radix_tree'
require_relative '../../lib/ruby_routes/utility/path_utility'

RSpec.describe RubyRoutes::Utility::PathUtility do
  let(:path_utility) { RubyRoutes::RadixTree.new }

  describe '#split_path' do
    it 'splits path on "/" and rejects empty segments' do
      expect(path_utility.split_path('/a/b/c')).to eq(['a', 'b', 'c'])
      expect(path_utility.split_path('///')).to eq([])  # Empties rejected
      expect(path_utility.split_path('/a//b')).to eq(['a', 'b'])  # Empty segments ignored
    end

    it 'ignores query strings' do
      expect(path_utility.split_path('/users?query=1')).to eq(['users'])
      expect(path_utility.split_path('/users/123?x=1&y=2')).to eq(['users', '123'])
    end

    it 'ignores URL fragments' do
      expect(path_utility.split_path('/users#fragment')).to eq(['users'])
      expect(path_utility.split_path('/users/123#frag')).to eq(['users', '123'])
    end

    it 'drops both query and fragment parts' do
      expect(path_utility.split_path('/users?query=1#frag')).to eq(['users'])
      expect(path_utility.split_path('/a/b?x=1#frag')).to eq(['a', 'b'])
    end

    it 'returns empty array for root or empty paths' do
      expect(path_utility.split_path('/')).to eq([])
      expect(path_utility.split_path('')).to eq([])
    end

    it 'handles complex paths with query and fragment' do
      expect(path_utility.split_path('/api/v1/users/123/posts?limit=10#section')).to eq(['api', 'v1', 'users', '123', 'posts'])
    end
  end

  describe '#normalize_path' do
    it 'ensures a leading slash' do
      expect(path_utility.normalize_path('users')).to eq('/users')
      expect(path_utility.normalize_path('users/123')).to eq('/users/123')
    end

    it 'removes trailing slash except for root' do
      expect(path_utility.normalize_path('users/')).to eq('/users')
      expect(path_utility.normalize_path('/users/')).to eq('/users')
      expect(path_utility.normalize_path('/')).to eq('/')
    end

    it 'leaves already normalized paths unchanged' do
      expect(path_utility.normalize_path('/users')).to eq('/users')
      expect(path_utility.normalize_path('/users/123')).to eq('/users/123')
    end

    it 'handles empty string' do
      expect(path_utility.normalize_path('')).to eq('/')
    end

    it 'handles paths with multiple trailing slashes' do
      expect(path_utility.normalize_path('users//')).to eq('/users/')
      # Note: The method only removes one trailing slash; if multiple, it may leave one
    end

    it 'handles root path' do
      expect(path_utility.normalize_path('/')).to eq('/')
    end

    it 'handles root path with a query string without raising an error' do
      # This test validates the fix for a bug where a path like '/?q=1'
      # would cause a `nil` slice error during path splitting.
      path = '/?q=1'
      expect { path_utility.split_path(path) }.not_to raise_error
      expect(path_utility.split_path(path)).to eq([])
    end
  end
end
