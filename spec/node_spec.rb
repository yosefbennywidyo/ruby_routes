require 'spec_helper'

RSpec.describe RubyRoutes::Node do
  let(:node) { RubyRoutes::Node.new }

  describe '#initialize' do
    it 'creates a new node with default values' do
      expect(node.is_endpoint).to be false
      expect(node.param_name).to be_nil
    end
  end

  describe '#add_handler' do
    it 'adds a handler for an HTTP method' do
      handler = double('handler')
      node.add_handler('GET', handler)
      
      expect(node.get_handler('GET')).to eq(handler)
      expect(node.is_endpoint).to be true
    end

    it 'handles multiple HTTP methods' do
      get_handler = double('get_handler')
      post_handler = double('post_handler')
      
      node.add_handler('GET', get_handler)
      node.add_handler('POST', post_handler)
      
      expect(node.get_handler('GET')).to eq(get_handler)
      expect(node.get_handler('POST')).to eq(post_handler)
    end
  end

  describe '#get_handler' do
    it 'returns nil for non-existent method' do
      expect(node.get_handler('GET')).to be_nil
    end

    it 'returns the correct handler for a method' do
      handler = double('handler')
      node.add_handler('GET', handler)
      
      expect(node.get_handler('GET')).to eq(handler)
    end
  end

  describe '#param_name' do
    it 'can set and get parameter name' do
      node.param_name = 'id'
      expect(node.param_name).to eq('id')
    end
  end

  describe '#traverse_for' do
    it 'handles traversal with segments' do
      # This is a complex method that requires segment objects
      # Testing basic functionality
      segments = ['users', '123']
      params = {}
      
      # The method returns [next_node, should_break]
      result = node.traverse_for('users', 0, segments, params)
      
      # Should return an array with two elements
      expect(result).to be_an(Array)
      expect(result.length).to eq(2)
    end
  end
end
