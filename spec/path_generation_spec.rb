# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyRoutes::Route::PathGeneration do
  let(:route) { RubyRoutes::Route.allocate } # Allocate an instance of Route

  before do
    route.extend(described_class) # Extend the instance with PathGeneration
  end

  describe '#build_generation_cache_key' do
    context 'when all required params are defaulted' do
      let(:required_params) { {} } # Simulate defaulted required params
      let(:param_names) { [:optional] }
      let(:optional_params_1) { { optional: 'value1' } }
      let(:optional_params_2) { { optional: 'value2' } }

      before do
        route.instance_variable_set(:@required_params, required_params) # Set instance variable directly
        route.instance_variable_set(:@param_names, param_names)
        allow(route).to receive(:cache_key_for_params).and_return('key1', 'key2')
      end

      it 'generates different cache keys for different optional params' do
        key1 = route.send(:build_generation_cache_key, optional_params_1)
        key2 = route.send(:build_generation_cache_key, optional_params_2)

        expect(key1).to eq('key1')
        expect(key2).to eq('key2')
        expect(key1).not_to eq(key2)
      end
    end
  end
end
