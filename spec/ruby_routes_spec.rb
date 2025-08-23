# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyRoutes do
  describe '.new' do
    it 'creates a new router instance' do
      router = RubyRoutes.new  # Changed from RubyRoutes::Router.new
      expect(router).to be_a(RubyRoutes::Router)
    end

    it 'accepts a block for route definition' do
      router = RubyRoutes.new do  # Changed from RubyRoutes::Router.new
        get '/', to: 'home#index'
      end

      expect(router.route_set.routes.size).to eq(1)
      expect(router.route_set.routes.first.path).to eq('/')
    end
  end

  describe '.draw' do
    it 'creates a router and yields to block' do
      router = RubyRoutes.draw do  # Changed from RubyRoutes::Router.build
        get '/about', to: 'pages#about'
      end

      expect(router.route_set.routes.size).to eq(1)
      expect(router.route_set.routes.first.path).to eq('/about')
    end
  end
end
