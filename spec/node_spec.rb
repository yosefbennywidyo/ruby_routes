# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyRoutes::Node do
  let(:node) { described_class.new }

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

    it 'is not an endpoint by default' do
      expect(node.is_endpoint).to be false
    end

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

    it 'returns the handler regardless of method case (normalizes internally)' do
      node.add_handler(:get, { controller: 'users', action: 'index' })
      expect(node.get_handler('get')).to eq({ controller: 'users', action: 'index' })
      expect(node.get_handler('GET')).to eq({ controller: 'users', action: 'index' })
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
    it 'returns nil when no children exist' do
      segments = %w[users 123]
      params = {}

      result, should_break = node.traverse_for('users', 0, segments, params)

      expect(result).to be_nil
      expect(should_break).to be false
      expect(params).to be_empty
    end

    it 'matches static children with O(1) lookup' do
      # Set up static child
      static_child = RubyRoutes::Node.new
      node.instance_variable_set(:@static_children, { 'users' => static_child })

      segments = %w[users 123]
      params = {}

      result, should_break = node.traverse_for('users', 0, segments, params)

      expect(result).to eq(static_child)
      expect(should_break).to be false
      expect(params).to be_empty # Static match doesn't capture params
    end

    it 'matches dynamic children and captures parameters' do
      # Set up dynamic child
      dynamic_child = RubyRoutes::Node.new
      dynamic_child.param_name = 'id'
      node.instance_variable_set(:@dynamic_child, dynamic_child)

      segments = %w[users 123]
      params = {}

      result, should_break = node.traverse_for('123', 0, segments, params)

      expect(result).to eq(dynamic_child)
      expect(should_break).to be false
      expect(params['id']).to eq('123')
    end

    it 'matches wildcard children and captures remaining path' do
      # Set up wildcard child
      wildcard_child = RubyRoutes::Node.new
      wildcard_child.param_name = 'path'
      node.instance_variable_set(:@wildcard_child, wildcard_child)

      segments = ['files', 'docs', 'readme.txt']
      params = {}

      result, should_break = node.traverse_for('docs', 1, segments, params)

      expect(result).to eq(wildcard_child)
      expect(should_break).to be true # Wildcard breaks traversal
      expect(params['path']).to eq('docs/readme.txt')
    end

    it 'handles wildcard with single remaining segment' do
      # Set up wildcard child
      wildcard_child = RubyRoutes::Node.new
      wildcard_child.param_name = 'file'
      node.instance_variable_set(:@wildcard_child, wildcard_child)

      segments = ['uploads', 'image.jpg']
      params = {}

      result, should_break = node.traverse_for('image.jpg', 1, segments, params)

      expect(result).to eq(wildcard_child)
      expect(should_break).to be true
      expect(params['file']).to eq('image.jpg') # Single segment, no join
    end

    it 'prioritizes static over dynamic matches' do
      # Set up both static and dynamic children
      static_child = RubyRoutes::Node.new
      dynamic_child = RubyRoutes::Node.new
      dynamic_child.param_name = 'id'

      node.instance_variable_set(:@static_children, { 'new' => static_child })
      node.instance_variable_set(:@dynamic_child, dynamic_child)

      segments = %w[users new]
      params = {}

      result, should_break = node.traverse_for('new', 1, segments, params)

      # Should match static, not dynamic
      expect(result).to eq(static_child)
      expect(should_break).to be false
      expect(params).to be_empty # No dynamic capture
    end

    it 'handles nil params gracefully' do
      # Set up dynamic child
      dynamic_child = RubyRoutes::Node.new
      dynamic_child.param_name = 'id'
      node.instance_variable_set(:@dynamic_child, dynamic_child)

      segments = %w[users 123]

      result, should_break = node.traverse_for('123', 0, segments, nil)

      expect(result).to eq(dynamic_child)
      expect(should_break).to be false
      # Should not crash when params is nil
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

    it 'returns the handler regardless of method case (normalizes internally)' do
      node.add_handler(:get, { controller: 'users', action: 'index' })
      expect(node.get_handler('get')).to eq({ controller: 'users', action: 'index' })
      expect(node.get_handler('GET')).to eq({ controller: 'users', action: 'index' })
    end

    it 'returns nil for unregistered methods' do
      node.add_handler(:get, { controller: 'users', action: 'index' })
      expect(node.get_handler('DELETE')).to be_nil
    end
  end
end
