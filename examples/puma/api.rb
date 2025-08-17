#!/usr/bin/env ruby

require 'rack'
# Prefer Puma handler for examples (install with `gem install puma` or add to Gemfile).
begin
  require 'puma'
rescue LoadError
  warn "puma gem not available — install with: gem install puma (falling back to WEBrick)"
end
# On recent Rubies WEBrick is a separate gem. Install with `gem install webrick`
begin
  require 'webrick'
rescue LoadError
  # no-op, fallback handling below will report if no handler available
end
require_relative '../../lib/ruby_routes'
require 'json'

# Define routes
router = RubyRoutes.draw do
  namespace :api do
    resources :users
  end
end

# Simple controller simulation
class Controller
  def initialize(env, params = {})
    @env = env
    @params = params
  end

  def render(content, status = 200, headers = {})
    [status, { 'Content-Type' => 'text/html' }.merge(headers), [content]]
  end

  def json(data, status = 200)
    [status, { 'Content-Type' => 'application/json' }, [data.to_json]]
  end
end

# API Users controller
module Api
  class UsersController < Controller
    def index
      users = [
        { id: 1, name: 'John Doe', email: 'john@example.com' },
        { id: 2, name: 'Jane Smith', email: 'jane@example.com' }
      ]
      json(users)
    end

    def show
      user = { id: @params['id'], name: 'User Name', email: 'user@example.com' }
      json(user)
    end
  end
end

# Rack application
class RouterApp
  def initialize(router)
    @router = router
  end

  def call(env)
    request_method = env['REQUEST_METHOD']
    request_path = env['PATH_INFO']

    # Try to match the route
    route_info = @router.route_set.match(request_method, request_path)

    if route_info
      # Extract controller and action
      controller_name = route_info[:controller]
      action_name = route_info[:action]
      params = route_info[:params]

      # Instantiate controller
      controller_class = get_controller_class(controller_name)
      controller = controller_class.new(env, params)

      # Call the action
      if controller.respond_to?(action_name)
        controller.send(action_name)
      else
        [404, { 'Content-Type' => 'text/plain' }, ['Action not found']]
      end
    else
      # No route matched
      [404, { 'Content-Type' => 'text/html' }, [<<~HTML]]
        <h1>404 - Not Found</h1>
        <p>The requested path "#{request_path}" was not found.</p>
        <p><a href="/">Go to Home</a></p>
      HTML
    end
  rescue => e
    [500, { 'Content-Type' => 'text/plain' }, ["Internal Server Error: #{e.message}"]]
  end

  private

  def get_controller_class(name)
    case name
    when 'api/users'
      Api::UsersController
    else
      raise "Unknown controller: #{name}"
    end
  end
end

# Create the Rack app
app = RouterApp.new(router)

# Start the server
if __FILE__ == $0
  puts "Starting Router Gem Demo Server on http://localhost:9292"
  puts "Routes defined:"
  router.route_set.routes.each do |route|
    puts "  #{route.methods.join(', ')} #{route.path} -> #{route.controller}##{route.action}"
  end
  puts

  # Prefer Puma handler when available, otherwise try WEBrick.
  handler =
    if defined?(Rack::Handler::Puma)
      Rack::Handler::Puma
    else
      begin
        Rack::Handler.get('puma')
      rescue LoadError, NameError
        # try WEBrick as fallback
        if defined?(Rack::Handler::WEBrick)
          Rack::Handler::WEBrick
        else
          begin
            Rack::Handler.get('webrick')
          rescue LoadError, NameError
            nil
          end
        end
      end
    end

  if handler
    handler.run app, Port: 9292
  else
    abort <<~MSG
      No Rack handler available (tried puma then webrick).
      - Install puma: gem install puma
      - Or install webrick: gem install webrick
      - Or run with Bundler: bundle exec ruby examples/rack_integration.rb
    MSG
  end
end
