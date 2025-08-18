require 'spec_helper'

RSpec.describe RubyRoutes::Node do
  describe '#add_handler' do
    let(:node) { RubyRoutes::Node.new }

    it 'adds handler and normalizes method to uppercase' do
      handler = { controller: 'users', action: 'index' }
      node.add_handler(:get, handler)
      
      expect(node.get_handler('GET')).to eq(handler)
      expect(node.is_endpoint).to be true
    end

    it 'normalizes string methods to uppercase' do
      handler = { controller: 'users', action: 'create' }
      node.add_handler('post', handler)
      
      expect(node.get_handler('POST')).to eq(handler)
    end

    it 'handles multiple methods on same node' do
      get_handler = { controller: 'users', action: 'show' }
      put_handler = { controller: 'users', action: 'update' }
      
      node.add_handler(:get, get_handler)
      node.add_handler(:put, put_handler)
      
      expect(node.get_handler('GET')).to eq(get_handler)
      expect(node.get_handler('PUT')).to eq(put_handler)
    end
  end
end
