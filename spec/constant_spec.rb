require 'ruby_routes/constant'

RSpec.describe RubyRoutes::Constant do
  describe '.segment_descriptor' do
    it 'returns static descriptor for regular string' do
      desc = RubyRoutes::Constant.segment_descriptor('foo')
      expect(desc[:type]).to eq(:static)
      expect(desc[:value]).to eq('foo')
    end

    it 'returns param descriptor for :id' do
      desc = RubyRoutes::Constant.segment_descriptor(':id')
      expect(desc[:type]).to eq(:param)
      expect(desc[:name]).to eq('id')
    end

    it 'returns splat descriptor for *splat' do
      desc = RubyRoutes::Constant.segment_descriptor('*splat')
      expect(desc[:type]).to eq(:splat)
      expect(desc[:name]).to eq('splat')
    end

    it 'returns default descriptor for empty string' do
      desc = RubyRoutes::Constant.segment_descriptor('')
      expect(desc[:type]).to eq(:static)
      expect(desc[:value]).to eq('')
    end
  end

  describe 'SEGMENTS' do
    it 'maps 42 to WildcardSegment' do
      expect(RubyRoutes::Constant::SEGMENTS[42].name).to eq('RubyRoutes::Segments::WildcardSegment')
    end

    it 'maps 58 to DynamicSegment' do
      expect(RubyRoutes::Constant::SEGMENTS[58].name).to eq('RubyRoutes::Segments::DynamicSegment')
    end

    it 'maps :default to StaticSegment' do
      expect(RubyRoutes::Constant::SEGMENTS[:default].name).to eq('RubyRoutes::Segments::StaticSegment')
    end
  end

  describe 'SEGMENT_MATCHERS' do
    it 'returns nil for default matcher' do
      expect(RubyRoutes::Constant::SEGMENT_MATCHERS[:default].call(nil, nil, nil, nil, nil)).to be_nil
    end
  end

  describe 'LRU strategies' do
    it 'returns a frozen instance for hit strategy' do
      expect(RubyRoutes::Constant::LRU_HIT_STRATEGY).to be_frozen
    end

    it 'returns a frozen instance for miss strategy' do
      expect(RubyRoutes::Constant::LRU_MISS_STRATEGY).to be_frozen
    end
  end
end
