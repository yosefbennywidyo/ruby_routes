# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyRoutes::Router do
  describe '#build' do
    it 'replays recorded calls on the router instance before freezing and finalizing' do
      router = RubyRoutes::Router.build do
        get '/health', to: 'system#health'
      end

      routes = router.route_set.routes
      expect(routes.size).to eq(1)
      expect(routes.first.path).to eq('/health')
      expect(routes.first.controller).to eq('system')
      expect(routes.first.action).to eq('health')
    end
  end
end
