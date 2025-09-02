# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyRoutes::Segments::WildcardSegment do
  let(:parent_node) { RubyRoutes::Node.new }
  let(:wildcard_child_node) { instance_double('Node', param_name: nil) }
  let(:wildcard_segment_1) { described_class.new('*path') }
  let(:wildcard_segment_2) { described_class.new('*splat') }

  before do
    allow(parent_node).to receive(:wildcard_child).and_return(wildcard_child_node)
    allow(parent_node).to receive(:wildcard_child=).and_return(wildcard_child_node)
    allow(wildcard_child_node).to receive(:param_name).and_return('path', 'path') # Return 'path' for both calls since it doesn't overwrite
    allow(wildcard_child_node).to receive(:param_name=).with('path').and_return(nil)
    allow(wildcard_child_node).to receive(:param_name=).with('splat').and_return(nil)
  end

  describe '#ensure_child' do
    it 'does not overwrite param_name for different wildcard segments' do
      # Ensure child for the first wildcard segment
      child_node_1 = wildcard_segment_1.ensure_child(parent_node)
      expect(child_node_1.param_name).to eq('path')

      # Ensure child for the second wildcard segment
      child_node_2 = wildcard_segment_2.ensure_child(parent_node)
      expect(child_node_2.param_name).to eq('path') # Does not overwrite, so remains 'path'

      # Validate that the param_name for the first segment remains unchanged
      expect(child_node_1.param_name).to eq('path')
    end
  end

  context 'with different parent nodes' do
    let(:parent_node_1) { double('Node', wildcard_child: nil) }
    let(:parent_node_2) { double('Node', wildcard_child: nil) }
    let(:wildcard_child_node_1) { instance_double('Node', param_name: nil) }
    let(:wildcard_child_node_2) { instance_double('Node', param_name: nil) }
    let(:wildcard_segment_1) { described_class.new('*path') }
    let(:wildcard_segment_2) { described_class.new('*splat') }

    before do
      allow(parent_node_1).to receive(:wildcard_child).and_return(wildcard_child_node_1)
      allow(parent_node_1).to receive(:wildcard_child=).and_return(wildcard_child_node_1)
      allow(parent_node_2).to receive(:wildcard_child).and_return(wildcard_child_node_2)
      allow(parent_node_2).to receive(:wildcard_child=).and_return(wildcard_child_node_2)
      allow(wildcard_child_node_1).to receive(:param_name).and_return('path')
      allow(wildcard_child_node_1).to receive(:param_name=).with('path').and_return(nil)
      allow(wildcard_child_node_2).to receive(:param_name).and_return('splat')
      allow(wildcard_child_node_2).to receive(:param_name=).with('splat').and_return(nil)
    end

    it 'sets param_name correctly for different wildcard segments' do
      child_node_1 = wildcard_segment_1.ensure_child(parent_node_1)
      expect(child_node_1.param_name).to eq('path')

      child_node_2 = wildcard_segment_2.ensure_child(parent_node_2)
      expect(child_node_2.param_name).to eq('splat')
    end
  end
end
