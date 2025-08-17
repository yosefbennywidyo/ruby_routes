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

# Define routes
router = RubyRoutes.draw do
  get '/', to: 'home#index'
  get '/users', as: :users, to: 'users#index'
  get '/users/:id', as: :user, to: 'users#show'
  post '/users', as: :create_user, to: 'users#create'
  put '/users/:id', as: :update_user, to: 'users#update'
  delete '/users/:id', as: :delete_user, to: 'users#destroy'

  resources :posts
  resources :comments
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

# Home controller
class HomeController < Controller
  def index
    render(<<~HTML)
      <h1>Welcome to Router Gem Demo</h1>
      <p>This is a simple demonstration of the Router gem.</p>
      <ul>
        <li><a href="/users">View Users</a></li>
        <li><a href="/posts">View Posts</a></li>
        <li><a href="/api/users">API Users</a></li>
      </ul>
    HTML
  end
end

# Users controller
class UsersController < Controller
  def index
    users = [
      { id: 1, name: 'John Doe', email: 'john@example.com' },
      { id: 2, name: 'Jane Smith', email: 'jane@example.com' }
    ]

    if @env['HTTP_ACCEPT']&.include?('application/json')
      json(users)
    else
      render(<<~HTML)
        <h1>Users</h1>
        <ul>
          #{users.map { |u| "<li><a href='/users/#{u[:id]}'>#{u[:name]}</a></li>" }.join}
        </ul>
        <p><a href="/">Back to Home</a></p>
      HTML
    end
  end

  def show
    user = { id: @params['id'], name: 'User Name', email: 'user@example.com' }

    if @env['HTTP_ACCEPT']&.include?('application/json')
      json(user)
    else
      render(<<~HTML)
        <h1>User #{user[:id]}</h1>
        <p><strong>Name:</strong> #{user[:name]}</p>
        <p><strong>Email:</strong> #{user[:email]}</p>
        <p><a href="/users">Back to Users</a></p>
      HTML
    end
  end

  def create
    render("User created with params: #{@params.inspect}", 201)
  end

  def update
    render("User #{@params['id']} updated with params: #{@params.inspect}")
  end

  def destroy
    render("User #{@params['id']} deleted", 200)
  end
end

# Posts controller
class PostsController < Controller
  def index
    posts = [
      { id: 1, title: 'First Post', content: 'This is the first post.' },
      { id: 2, title: 'Second Post', content: 'This is the second post.' }
    ]

    render(<<~HTML)
      <h1>Posts</h1>
      <ul>
        #{posts.map { |p| "<li><a href='/posts/#{p[:id]}'>#{p[:title]}</a></li>" }.join}
      </ul>
      <p><a href="/">Back to Home</a></p>
    HTML
  end

  def show
    post = { id: @params['id'], title: 'Post Title', content: 'Post content here.' }

    render(<<~HTML)
      <h1>#{post[:title]}</h1>
      <p>#{post[:content]}</p>
      <p><a href="/posts">Back to Posts</a></p>
    HTML
  end
end
=begin
# API Users controller
class Api::UsersController < Controller
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
=end
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
    when 'home'
      HomeController
    when 'users'
      UsersController
    when 'posts'
      PostsController
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
