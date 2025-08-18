require 'spec_helper'

RSpec.describe RubyRoutes::Node do
  describe '#add_handler' do
    let(:node) { described_class.new }

    it 'is not an endpoint by default' do
      expect(node.is_endpoint).to be false
    end

    it 'adds handler and normalizes method to uppercase' do
      handler = { controller: 'users', action: 'index' }
      node.add_handler(:get, handler)

      expect(node.get_handler('GET')).to eq(handler)
      expect(node.is_endpoint).to be true
    end

    it 'overwrites an existing handler for the same method' do
      initial_handler = { controller: 'users', action: 'show' }
      new_handler = { controller: 'users', action: 'show_v2' }

      node.add_handler(:get, initial_handler)
      node.add_handler(:get, new_handler)

      expect(node.get_handler('GET')).to eq(new_handler)
      expect(node.is_endpoint).to be true
    end

    it 'normalizes string methods to uppercase' do
      handler = { controller: 'users', action: 'create' }
      node.add_handler('post', handler)

      expect(node.get_handler('POST')).to eq(handler)
      expect(node.is_endpoint).to be true
    end

    it 'handles multiple methods on same node' do
      get_handler = { controller: 'users', action: 'show' }
      put_handler = { controller: 'users', action: 'update' }

      node.add_handler(:get, get_handler)
      node.add_handler(:put, put_handler)

      expect(node.get_handler('GET')).to eq(get_handler)
      expect(node.get_handler('PUT')).to eq(put_handler)
      expect(node.is_endpoint).to be true
    end

    it 'does not normalize in get_handler (requires upstream normalization)' do
      node.add_handler(:get, { controller: 'users', action: 'index' })
      expect(node.get_handler('get')).to be_nil
      expect(node.get_handler('GET')).to eq({ controller: 'users', action: 'index' })
    end

    it 'overwrites handler for the same method' do
      first = { controller: 'users', action: 'old' }
      second = { controller: 'users', action: 'new' }
      node.add_handler(:get, first)
      node.add_handler(:get, second)
      expect(node.get_handler('GET')).to eq(second)
    end
  end
end
