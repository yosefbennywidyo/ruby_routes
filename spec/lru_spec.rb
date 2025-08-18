require 'spec_helper'

RSpec.describe RubyRoutes::Route::SmallLru do
  let(:lru) { RubyRoutes::Route::SmallLru.new(3) }

  describe '#initialize' do
    it 'creates LRU with specified max size' do
      expect(lru.instance_variable_get(:@max_size)).to eq(3)
    end

    it 'initializes counters to zero' do
      expect(lru.hits).to eq(0)
      expect(lru.misses).to eq(0)
      expect(lru.evictions).to eq(0)
    end

    it 'uses default max size when not specified' do
      default_lru = RubyRoutes::Route::SmallLru.new
      expect(default_lru.instance_variable_get(:@max_size)).to eq(1024)
    end

    it 'initializes with strategy objects' do
      expect(lru.instance_variable_get(:@hit_strategy)).to be_a(RubyRoutes::LruStrategies::HitStrategy)
      expect(lru.instance_variable_get(:@miss_strategy)).to be_a(RubyRoutes::LruStrategies::MissStrategy)
    end
  end

  describe '#set' do
    it 'stores key-value pairs' do
      result = lru.set('key1', 'value1')
      expect(result).to eq('value1')
    end

    it 'updates existing keys by moving them to end' do
      lru.set('key1', 'value1')
      lru.set('key2', 'value2')
      lru.set('key1', 'updated_value1')
      
      # key1 should now be at the end (most recent)
      hash = lru.instance_variable_get(:@h)
      expect(hash.keys.last).to eq('key1')
      expect(hash['key1']).to eq('updated_value1')
    end

    it 'evicts oldest entry when max size exceeded' do
      lru.set('key1', 'value1')
      lru.set('key2', 'value2')
      lru.set('key3', 'value3')
      lru.set('key4', 'value4') # Should evict key1
      
      hash = lru.instance_variable_get(:@h)
      expect(hash.keys).not_to include('key1')
      expect(hash.keys).to include('key4')
      expect(lru.evictions).to eq(1)
    end

    it 'increments eviction counter on eviction' do
      4.times { |i| lru.set("key#{i}", "value#{i}") }
      expect(lru.evictions).to eq(1)
      
      lru.set('key5', 'value5')
      expect(lru.evictions).to eq(2)
    end
  end

  describe '#get' do
    context 'when key exists (cache hit)' do
      before do
        lru.set('key1', 'value1')
        lru.set('key2', 'value2')
      end

      it 'returns the value' do
        result = lru.get('key1')
        expect(result).to eq('value1')
      end

      it 'moves accessed key to end (most recent)' do
        lru.get('key1') # Access key1
        
        hash = lru.instance_variable_get(:@h)
        expect(hash.keys.last).to eq('key1')
      end

      it 'increments hit counter' do
        expect { lru.get('key1') }.to change { lru.hits }.by(1)
      end
    end

    context 'when key does not exist (cache miss)' do
      it 'returns nil' do
        result = lru.get('nonexistent')
        expect(result).to be_nil
      end

      it 'increments miss counter' do
        expect { lru.get('nonexistent') }.to change { lru.misses }.by(1)
      end
    end
  end

  describe '#increment_hits' do
    it 'increments the hits counter' do
      expect { lru.increment_hits }.to change { lru.hits }.by(1)
    end
  end

  describe '#increment_misses' do
    it 'increments the misses counter' do
      expect { lru.increment_misses }.to change { lru.misses }.by(1)
    end
  end

  describe 'LRU behavior' do
    it 'maintains least recently used order' do
      lru.set('a', 1)
      lru.set('b', 2)
      lru.set('c', 3)
      
      # Access 'a' to make it most recent
      lru.get('a')
      
      # Add new item, should evict 'b' (least recent)
      lru.set('d', 4)
      
      hash = lru.instance_variable_get(:@h)
      expect(hash.keys).to eq(['c', 'a', 'd'])
      expect(hash.keys).not_to include('b')
    end

    it 'handles mixed get/set operations correctly' do
      lru.set('x', 10)
      lru.set('y', 20)
      lru.set('z', 30)
      
      # Access y and x
      lru.get('y')
      lru.get('x')
      
      # Add new item, should evict z
      lru.set('w', 40)
      
      hash = lru.instance_variable_get(:@h)
      expect(hash.keys).not_to include('z')
      expect(hash.keys).to include('y', 'x', 'w')
    end
  end

  describe 'performance characteristics' do
    it 'handles large number of operations efficiently' do
      large_lru = RubyRoutes::Route::SmallLru.new(100)
      
      # Add 150 items (should cause 50 evictions)
      150.times { |i| large_lru.set("key#{i}", "value#{i}") }
      
      expect(large_lru.evictions).to eq(50)
      
      # Hash should contain exactly 100 items
      hash = large_lru.instance_variable_get(:@h)
      expect(hash.size).to eq(100)
    end
  end
end

RSpec.describe 'LRU Strategies' do
  describe RubyRoutes::LruStrategies::HitStrategy do
    let(:strategy) { RubyRoutes::LruStrategies::HitStrategy.new }
    let(:lru) { RubyRoutes::Route::SmallLru.new(3) }

    it 'increments hit counter' do
      lru.set('key1', 'value1')
      
      expect { strategy.call(lru, 'key1') }.to change { lru.hits }.by(1)
    end

    it 'moves accessed key to end of hash' do
      lru.set('key1', 'value1')
      lru.set('key2', 'value2')
      
      # Access key1 via strategy
      result = strategy.call(lru, 'key1')
      
      expect(result).to eq('value1')
      
      # key1 should now be at the end
      hash = lru.instance_variable_get(:@h)
      expect(hash.keys.last).to eq('key1')
    end

    it 'returns the value for the accessed key' do
      lru.set('test_key', 'test_value')
      
      result = strategy.call(lru, 'test_key')
      expect(result).to eq('test_value')
    end

    it 'handles accessing the same key multiple times' do
      lru.set('key1', 'value1')
      
      3.times { strategy.call(lru, 'key1') }
      
      expect(lru.hits).to eq(3)
    end
  end

  describe RubyRoutes::LruStrategies::MissStrategy do
    let(:strategy) { RubyRoutes::LruStrategies::MissStrategy.new }
    let(:lru) { RubyRoutes::Route::SmallLru.new(3) }

    it 'increments miss counter' do
      expect { strategy.call(lru, 'nonexistent') }.to change { lru.misses }.by(1)
    end

    it 'returns nil for any key' do
      result = strategy.call(lru, 'any_key')
      expect(result).to be_nil
    end

    it 'does not modify the hash' do
      lru.set('existing', 'value')
      original_hash = lru.instance_variable_get(:@h).dup
      
      strategy.call(lru, 'nonexistent')
      
      current_hash = lru.instance_variable_get(:@h)
      expect(current_hash).to eq(original_hash)
    end

    it 'handles multiple misses correctly' do
      5.times { |i| strategy.call(lru, "miss#{i}") }
      
      expect(lru.misses).to eq(5)
    end
  end

  describe 'strategy integration' do
    let(:lru) { RubyRoutes::Route::SmallLru.new(2) }

    it 'uses correct strategy based on key existence' do
      # Set up some data
      lru.set('exists', 'value')
      
      # Reset counters to test strategy selection
      lru.instance_variable_set(:@hits, 0)
      lru.instance_variable_set(:@misses, 0)
      
      # Test hit
      lru.get('exists')
      expect(lru.hits).to eq(1)
      expect(lru.misses).to eq(0)
      
      # Test miss
      lru.get('does_not_exist')
      expect(lru.hits).to eq(1)
      expect(lru.misses).to eq(1)
    end
  end
end
