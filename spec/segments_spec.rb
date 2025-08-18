require 'spec_helper'

RSpec.describe 'Segment Classes' do
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
  end

  describe RubyRoutes::Segments::WildcardSegment do
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
