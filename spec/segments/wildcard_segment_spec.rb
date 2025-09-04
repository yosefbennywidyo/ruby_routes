# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyRoutes::Segments::WildcardSegment do
  let(:parent_node) { RubyRoutes::Node.new }
  let(:wildcard_child_node) { instance_double('Node', param_name: nil) }
  let(:wildcard_segment_1) { described_class.new('*path') }
  let(:wildcard_segment_2) { described_class.new('*splat') }

  let(:parent_node) { RubyRoutes::Node.new }
  let(:wildcard_segment_1) { described_class.new('*path') }
  let(:wildcard_segment_2) { described_class.new('*splat') }

  # No stubs — exercise real behavior

  describe '#ensure_child' do
    it 'does not overwrite param_name for different wildcard segments' do
      child_node_1 = wildcard_segment_1.ensure_child(parent_node)
      child_node_2 = wildcard_segment_2.ensure_child(parent_node)
      expect(child_node_1).to be(child_node_2)
      expect(child_node_2.param_name).to eq('path')
    end
  end

  context 'with different parent nodes' do
    let(:parent_node_1) { double('Node', wildcard_child: nil) }
    let(:parent_node_2) { double('Node', wildcard_child: nil) }
    let(:wildcard_child_node_1) { instance_double('Node', param_name: nil) }
    let(:wildcard_child_node_2) { instance_double('Node', param_name: nil) }
    let(:wildcard_segment_1) { described_class.new('*path') }
    let(:wildcard_segment_2) { described_class.new('*splat') }

  context 'with different parent nodes' do
    let(:parent_node_1) { RubyRoutes::Node.new }
    let(:parent_node_2) { RubyRoutes::Node.new }
    let(:wildcard_segment_1) { described_class.new('*path') }
    let(:wildcard_segment_2) { described_class.new('*splat') }

    # No stubs — exercise real behavior
  end
  end
end
