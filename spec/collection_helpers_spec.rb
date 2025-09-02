# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyRoutes::RouteSet::CollectionHelpers do
  let(:radix_tree) { double('RadixTree', add: nil) }
  let(:dummy_class) do
    Class.new do
      include RubyRoutes::RouteSet::CollectionHelpers

      def initialize(radix_tree)
        @routes = []
        @radix_tree = radix_tree
        @named_routes = {}
      end
    end
  end

  let(:collection_helper) { dummy_class.new(radix_tree) }
  let(:route) { double('Route', path: '/test', methods: [:get], name: 'test_route', named?: true) }

  describe 'double insertion bug' do
    it 'does not allow the same route to be added twice' do
      collection_helper.add_to_collection(route)
      collection_helper.add_to_collection(route)

      expect(collection_helper.size).to eq(1)
      expect(collection_helper.each.to_a).to eq([route])
      expect(collection_helper.include?(route)).to be true
      expect(collection_helper.find_named_route('test_route')).to eq(route)
    end
  end
end
