require 'spec_helper'

RSpec.describe 'String Extensions' do
  describe '#singularize' do
    it 'singularizes regular plurals' do
      expect('users'.singularize).to eq('user')
      expect('posts'.singularize).to eq('post')
      expect('categories'.singularize).to eq('category')
    end

    it 'handles words ending in -ies' do
      expect('companies'.singularize).to eq('company')
      expect('stories'.singularize).to eq('story')
    end

    it 'returns same word if already singular' do
      expect('user'.singularize).to eq('user')
      expect('post'.singularize).to eq('post')
    end
  end

  describe '#pluralize' do
    it 'pluralizes regular words' do
      expect('user'.pluralize).to eq('users')
      expect('post'.pluralize).to eq('posts')
      expect('comment'.pluralize).to eq('comments')
    end

    it 'handles words ending in -y' do
      expect('category'.pluralize).to eq('categories')
      expect('company'.pluralize).to eq('companies')
    end

    it 'returns same word if already plural' do
      expect('users'.pluralize).to eq('users')
      expect('posts'.pluralize).to eq('posts')
    end
  end
end
