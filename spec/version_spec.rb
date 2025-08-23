# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'RubyRoutes::VERSION' do
  it 'has a version number' do
    expect(RubyRoutes::VERSION).not_to be nil
    expect(RubyRoutes::VERSION).to be_a(String)
    expect(RubyRoutes::VERSION).to match(/\d+\.\d+\.\d+/)
  end
end
