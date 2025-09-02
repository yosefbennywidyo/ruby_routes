# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyRoutes::RadixTree do
  let(:tree) { described_class.new }

  describe '#find' do
    it 'handles traversal failure on first segment without NPE' do
      tree.add('/a/b', ['GET'], 'handler')
      result = tree.find('/c/b', 'GET')
      expect(result).to eq([nil, {}])
    end

    it 'falls back to best candidate when final node fails' do
      tree.add('/a', ['GET'], 'handler_a')
      # Add '/a/b' but assume no handler or constraints fail
      tree.add('/a/b', ['GET'], nil) # Simulate no handler
      result = tree.find('/a/b', 'GET')
      # Should fall back to best candidate '/a'
      expect(result).to eq(['handler_a', {}])
    end
  end
end
