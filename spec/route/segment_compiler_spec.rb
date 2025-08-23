# frozen_string_literal: true

require 'spec_helper'
require 'set'

RSpec.describe RubyRoutes::Route::SegmentCompiler do
  let(:dummy_route) do
    Class.new do
      include RubyRoutes::Route::SegmentCompiler
      include RubyRoutes::Utility::PathUtility

      attr_accessor :path, :compiled_segments, :defaults, :static_path, :param_names, :required_params,
                    :required_params_set

      def initialize
        @defaults = {}
        @compiled_segments = []
      end
    end.new
  end

  describe '#compile_segments' do
    it 'compiles root path to empty array' do
      dummy_route.path = '/'
      dummy_route.send(:compile_segments)
      expect(dummy_route.compiled_segments).to eq([])
    end

    it 'compiles static path segments' do
      dummy_route.path = '/users/posts'
      dummy_route.send(:compile_segments)
      expect(dummy_route.compiled_segments).to eq([
        { type: :static, value: 'users' },
        { type: :static, value: 'posts' }
      ])
    end

    it 'compiles dynamic segments' do
      dummy_route.path = '/users/:id'
      dummy_route.send(:compile_segments)
      expect(dummy_route.compiled_segments).to eq([
        { type: :static, value: 'users' },
        { type: :param, name: 'id' }
      ])
    end

    it 'compiles wildcard segments' do
      dummy_route.path = '/files/*path'
      dummy_route.send(:compile_segments)
      expect(dummy_route.compiled_segments).to eq([
        { type: :static, value: 'files' },
        { type: :splat, name: 'path' }
      ])
    end

    it 'ignores empty segments' do
      dummy_route.path = '/users//posts'
      dummy_route.send(:compile_segments)
      expect(dummy_route.compiled_segments).to eq([
        { type: :static, value: 'users' },
        { type: :static, value: 'posts' }
      ])
    end
  end

  describe '#compile_required_params' do
    it 'sets param_names and required_params for dynamic segments' do
      dummy_route.compiled_segments = [
        { type: :static, value: 'users' },
        { type: :param, name: 'id' },
        { type: :param, name: 'action' }
      ]
      dummy_route.send(:compile_required_params)
      expect(dummy_route.param_names).to eq(['id', 'action'])
      expect(dummy_route.required_params).to eq(['id', 'action'])
      expect(dummy_route.required_params_set).to eq(Set.new(['id', 'action']))
    end

    it 'excludes params with defaults from required_params' do
      dummy_route.compiled_segments = [
        { type: :static, value: 'users' },
        { type: :param, name: 'id' },
        { type: :param, name: 'format' }
      ]
      dummy_route.defaults = { 'format' => 'html' }
      dummy_route.send(:compile_required_params)
      expect(dummy_route.param_names).to eq(['id', 'format'])
      expect(dummy_route.required_params).to eq(['id'])
      expect(dummy_route.required_params_set).to eq(Set.new(['id']))
    end

    it 'handles empty compiled_segments' do
      dummy_route.compiled_segments = []
      dummy_route.send(:compile_required_params)
      expect(dummy_route.param_names).to eq([])
      expect(dummy_route.required_params).to eq([])
      expect(dummy_route.required_params_set).to eq(Set.new)
    end
  end

  describe '#check_static_path' do
    it 'sets static_path for all static segments' do
      dummy_route.compiled_segments = [
        { type: :static, value: 'users' },
        { type: :static, value: 'posts' }
      ]
      dummy_route.send(:check_static_path)
      expect(dummy_route.static_path).to eq('/users/posts')
    end

    it 'does not set static_path if any segment is dynamic' do
      dummy_route.compiled_segments = [
        { type: :static, value: 'users' },
        { type: :param, name: 'id' }
      ]
      dummy_route.send(:check_static_path)
      expect(dummy_route.static_path).to be_nil
    end

    it 'sets static_path to root for empty segments' do
      dummy_route.compiled_segments = []
      dummy_route.send(:check_static_path)
      expect(dummy_route.static_path).to eq('/')
    end
  end

  describe '#generate_static_path' do
    it 'generates path from static segments' do
      dummy_route.compiled_segments = [
        { type: :static, value: 'users' },
        { type: :static, value: 'posts' }
      ]
      expect(dummy_route.send(:generate_static_path)).to eq('/users/posts')
    end

    it 'returns root for empty segments' do
      dummy_route.compiled_segments = []
      expect(dummy_route.send(:generate_static_path)).to eq('/')
    end
  end

  describe '#extract_path_params_fast' do
    it 'returns empty hash for root path match' do
      dummy_route.compiled_segments = []
      dummy_route.path = '/'
      result = dummy_route.send(:extract_path_params_fast, '/')
      expect(result).to eq({})
    end

    it 'returns nil for non-matching path' do
      dummy_route.compiled_segments = [
        { type: :static, value: 'users' },
        { type: :param, name: 'id' }
      ]
      result = dummy_route.send(:extract_path_params_fast, '/posts/123')
      expect(result).to be_nil
    end

    it 'extracts params for dynamic segments' do
      dummy_route.compiled_segments = [
        { type: :static, value: 'users' },
        { type: :param, name: 'id' }
      ]
      result = dummy_route.send(:extract_path_params_fast, '/users/123')
      expect(result).to eq({ 'id' => '123' })
    end

    it 'extracts params for wildcard segments' do
      dummy_route.compiled_segments = [
        { type: :static, value: 'files' },
        { type: :splat, name: 'path' }
      ]
      result = dummy_route.send(:extract_path_params_fast, '/files/docs/readme.txt')
      expect(result).to eq({ 'path' => 'docs/readme.txt' })
    end

    it 'returns nil if path has too few segments for non-wildcard' do
      dummy_route.compiled_segments = [
        { type: :static, value: 'users' },
        { type: :param, name: 'id' }
      ]
      result = dummy_route.send(:extract_path_params_fast, '/users')
      expect(result).to be_nil
    end
  end

  describe '#extract_params_from_parts' do
    it 'extracts params correctly' do
      dummy_route.compiled_segments = [
        { type: :static, value: 'users' },
        { type: :param, name: 'id' },
        { type: :splat, name: 'path' }
      ]
      parts = ['users', '123', 'posts', 'comments']
      result = dummy_route.send(:extract_params_from_parts, parts)
      expect(result).to eq({ 'id' => '123', 'path' => 'posts/comments' })
    end

    it 'returns nil for static mismatch' do
      dummy_route.compiled_segments = [
        { type: :static, value: 'users' },
        { type: :param, name: 'id' }
      ]
      parts = ['posts', '123']
      result = dummy_route.send(:extract_params_from_parts, parts)
      expect(result).to be_nil
    end
  end

  describe '#extract_path_params_fast' do
    it 'extracts params for wildcard segments' do
      route = RubyRoutes::Route.new('/files/*path', to: 'files#show')
      result = route.extract_path_params_fast('/files/docs/readme.txt')
      expect(result).to eq({ 'path' => 'docs/readme.txt' })
    end

    it 'extracts params correctly' do
      route = RubyRoutes::Route.new('/users/:id/*path', to: 'users#show')
      result = route.extract_path_params_fast('/users/123/posts/comments')
      expect(result).to eq({ 'id' => '123', 'path' => 'posts/comments' })
    end
  end

  describe '#extract_params_from_parts' do
    it 'extracts params correctly' do
      route = RubyRoutes::Route.new('/users/:id/*path', to: 'users#show')
      path_parts = ['users', '123', 'posts', 'comments']
      result = route.send(:extract_params_from_parts, path_parts)
      expect(result).to eq({ 'id' => '123', 'path' => 'posts/comments' })
    end
  end
end
