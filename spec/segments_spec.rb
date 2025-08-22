require 'spec_helper'

RSpec.describe 'Segment Classes' do
  let(:segment) { RubyRoutes::Segments::StaticSegment.new('foo') }
  let(:node) { RubyRoutes::Node.new }

  before do
    node.static_children['foo'] = RubyRoutes::Node.new
  end

  describe '#match' do
    it 'returns the child node when text matches' do
      result, _ = segment.match(node, 'foo', 0, [], {})
      expect(result).to eq(node.static_children['foo'])
    end

    it 'returns nil when text does not match' do
      result, _ = segment.match(node, 'bar', 0, [], {})
      expect(result).to be_nil
    end

    it 'returns false as the second element' do
      _, flag = segment.match(node, 'foo', 0, [], {})
      expect(flag).to be(false)
    end
  end

  describe RubyRoutes::Segment do
    describe '.for' do
      it 'creates static segment for regular text' do
        segment = RubyRoutes::Segment.for('users')
        expect(segment).to be_a(RubyRoutes::Segments::StaticSegment)
      end

      it 'creates dynamic segment for parameter text' do
        segment = RubyRoutes::Segment.for(':id')
        expect(segment).to be_a(RubyRoutes::Segments::DynamicSegment)
      end

      it 'creates wildcard segment for splat text' do
        segment = RubyRoutes::Segment.for('*path')
        expect(segment).to be_a(RubyRoutes::Segments::WildcardSegment)
      end
    end

    describe '#wildcard?' do
      it 'returns false by default' do
        segment = RubyRoutes::Segment.new
        expect(segment.wildcard?).to be false
      end
    end
  end

  describe RubyRoutes::Segments::StaticSegment do
    let(:segment) { RubyRoutes::Segments::StaticSegment.new('users') }

    describe '#wildcard?' do
      it 'returns false' do
        expect(segment.wildcard?).to be false
      end
    end

    describe '#ensure_child' do
      it 'creates or finds child node' do
        parent = RubyRoutes::Node.new
        child = segment.ensure_child(parent)

        expect(child).to be_a(RubyRoutes::Node)
      end
    end
  end

  describe RubyRoutes::Segments::DynamicSegment do
    let(:segment) { RubyRoutes::Segments::DynamicSegment.new(':id') }

    describe '#initialize' do
      it 'extracts parameter name from text' do
        expect(segment.instance_variable_get(:@name)).to eq('id')
      end
    end

    describe '#wildcard?' do
      it 'returns false' do
        expect(segment.wildcard?).to be false
      end
    end

    describe '#ensure_child' do
      it 'creates child node with parameter name' do
        parent = RubyRoutes::Node.new
        child = segment.ensure_child(parent)

        expect(child).to be_a(RubyRoutes::Node)
        expect(child.param_name).to eq('id')
      end
    end

    let(:segment) { described_class.new(':id') }
    let(:node) { RubyRoutes::Node.new }
    let(:params) { {} }

    describe '#match' do
      context 'when dynamic_child exists' do
        before do
          node.dynamic_child = RubyRoutes::Node.new
          node.dynamic_child.param_name = 'id'
        end

        it 'returns the dynamic child node' do
          result, flag = segment.match(node, '123', 0, [], params)
          expect(result).to eq(node.dynamic_child)
          expect(flag).to be false
        end

        it 'sets the param value' do
          segment.match(node, '456', 0, [], params)
          expect(params['id']).to eq('456')
        end

        it 'does not set params if params is nil' do
          result, flag = segment.match(node, '789', 0, [], nil)
          expect(result).to eq(node.dynamic_child)
          expect(flag).to be false
        end
      end

      context 'when dynamic_child does not exist' do
        it 'returns [nil, false]' do
          result, flag = segment.match(node, '123', 0, [], params)
          expect(result).to be_nil
          expect(flag).to be false
        end
      end
    end
  end

  describe RubyRoutes::Segments::WildcardSegment do
    let(:segment) { RubyRoutes::Segments::WildcardSegment.new('*splat') }
    let(:node) { RubyRoutes::Node.new }
    let(:params) { {} }

    before do
      node.wildcard_child = RubyRoutes::Node.new
      node.wildcard_child.param_name = 'splat'
    end

    describe '#match' do
      it 'returns the wildcard child and sets params when wildcard_child exists' do
        segments = %w[foo bar baz]
        result, flag = segment.match(node, 'foo', 0, segments, params)
        expect(result).to eq(node.wildcard_child)
        expect(flag).to be true
        expect(params['splat']).to eq('foo/bar/baz')
      end

      it 'returns [nil, false] when wildcard_child does not exist' do
        node_without_child = RubyRoutes::Node.new
        result, flag = segment.match(node_without_child, 'foo', 0, %w[foo bar], params)
        expect(result).to be_nil
        expect(flag).to be false
      end

      it 'does not set params if params is nil' do
        result, flag = segment.match(node, 'foo', 0, %w[foo bar], nil)
        expect(result).to eq(node.wildcard_child)
        expect(flag).to be true
      end
    end

    let(:segment) { RubyRoutes::Segments::WildcardSegment.new('*path') }

    describe '#initialize' do
      it 'extracts parameter name from text' do
        expect(segment.instance_variable_get(:@name)).to eq('path')
      end
    end

    describe '#wildcard?' do
      it 'returns true' do
        expect(segment.wildcard?).to be true
      end
    end

    describe '#ensure_child' do
      it 'creates child node with parameter name' do
        parent = RubyRoutes::Node.new
        child = segment.ensure_child(parent)

        expect(child).to be_a(RubyRoutes::Node)
        expect(child.param_name).to eq('path')
      end
    end
  end

  describe RubyRoutes::Segments::BaseSegment do
    let(:segment) { RubyRoutes::Segments::BaseSegment.new }

    describe '#wildcard?' do
      it 'returns false by default' do
        expect(segment.wildcard?).to be false
      end
    end

    describe '#ensure_child' do
      it 'raises NotImplementedError' do
        parent = RubyRoutes::Node.new
        expect {
          segment.ensure_child(parent)
        }.to raise_error(NotImplementedError)
      end
    end

    describe '#match' do
      it 'raises NotImplementedError' do
        expect {
          segment.match(nil, nil, nil, nil, nil)
        }.to raise_error(NotImplementedError)
      end
    end
  end
end
