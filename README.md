# Ruby Routes Gem

A lightweight, flexible routing system for Ruby that provides a Rails-like DSL for defining and matching HTTP routes.

## Features

- **Rails-like DSL**: Familiar syntax for defining routes
- **HTTP Method Support**: GET, POST, PUT, PATCH, DELETE, and custom methods
- **RESTful Resources**: Automatic generation of RESTful routes
- **Nested Routes**: Support for nested resources and namespaces
- **Route Constraints**: Add constraints to routes (regex, etc.)
- **Named Routes**: Generate URLs from route names
- **Path Generation**: Build URLs with parameters
- **Scope Support**: Group routes with common options
- **Concerns**: Reusable route groups
- **Lightweight**: Minimal dependencies, fast performance

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'ruby_routes'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install ruby_routes
```

## Basic Usage

### Simple Routes

```ruby
require 'ruby_routes'

router = RubyRoutes.draw do
  get '/', to: 'home#index'
  get '/about', to: 'pages#about'
  post '/users', to: 'users#create'
  put '/users/:id', to: 'users#update'
  delete '/users/:id', to: 'users#destroy'
end
```

### RESTful Resources

```ruby
router = RubyRoutes.draw do
  resources :users
  resources :posts
  resources :comments
end
```

This creates the following routes:
- `GET /users` → `users#index`
- `GET /users/new` → `users#new`
- `POST /users` → `users#create`
- `GET /users/:id` → `users#show`
- `GET /users/:id/edit` → `users#edit`
- `PUT /users/:id` → `users#update`
- `PATCH /users/:id` → `users#update`
- `DELETE /users/:id` → `users#destroy`

### Named Routes

```ruby
router = RubyRoutes.draw do
  get '/users', as: :users, to: 'users#index'
  get '/users/:id', as: :user, to: 'users#show'
  post '/users', as: :create_user, to: 'users#create'
end

# Generate paths
router.route_set.generate_path(:users)           # => "/users"
router.route_set.generate_path(:user, id: '123') # => "/users/123"
```

### Namespaces

```ruby
router = RubyRoutes.draw do
  namespace :admin do
    resources :users
    resources :posts
  end
end

# Creates routes like:
# GET /admin/users → admin/users#index
# GET /admin/users/:id → admin/users#show
# etc.
```

### Nested Resources

```ruby
router = RubyRoutes.draw do
  resources :categories do
    resources :products
  end
end

# Creates routes like:
# GET /categories/:category_id/products → products#index
# GET /categories/:category_id/products/:id → products#show
# etc.
```

### Scopes and Constraints

```ruby
router = RubyRoutes.draw do
  scope constraints: { id: /\d+/ } do
    get '/users/:id', to: 'users#show'
  end
  
  scope defaults: { format: 'html' } do
    get '/posts', to: 'posts#index'
  end
end
```

### Concerns

```ruby
router = RubyRoutes.draw do
  concern :commentable do
    resources :comments
  end
  
  resources :posts do
    concerns :commentable
  end
  
  resources :articles do
    concerns :commentable
  end
end
```

### Root Route

```ruby
router = RubyRoutes.draw do
  root to: 'home#index'
end
```

## Route Matching

```ruby
router = RubyRoutes.draw do
  get '/users/:id', to: 'users#show'
  post '/users', to: 'users#create'
end

# Match a request
result = router.route_set.match('GET', '/users/123')
if result
  puts "Controller: #{result[:controller]}"
  puts "Action: #{result[:action]}"
  puts "Params: #{result[:params]}"
  # => Controller: users
  # => Action: show
  # => Params: {"id"=>"123"}
end
```

## Path Generation

```ruby
router = RubyRoutes.draw do
  get '/users/:id', as: :user, to: 'users#show'
  get '/posts/:id/comments/:comment_id', as: :post_comment, to: 'comments#show'
end

# Generate paths
router.route_set.generate_path(:user, id: '123')
# => "/users/123"

router.route_set.generate_path(:post_comment, id: '456', comment_id: '789')
# => "/posts/456/comments/789"
```

## Integration with Rack

```ruby
require 'rack'
require 'ruby_routes'

# Define routes
router = RubyRoutes.draw do
  get '/', to: 'home#index'
  get '/users', to: 'users#index'
  get '/users/:id', to: 'users#show'
end

# Create Rack app
class RubyRoutesApp
  def initialize(router)
    @router = router
  end
  
  def call(env)
    request_method = env['REQUEST_METHOD']
    request_path = env['PATH_INFO']
    
    route_info = @router.route_set.match(request_method, request_path)
    
    if route_info
      # Handle the request
      controller = route_info[:controller]
      action = route_info[:action]
      params = route_info[:params]
      
      # Your controller logic here
      [200, {'Content-Type' => 'text/html'}, ["Hello from #{controller}##{action}"]]
    else
      [404, {'Content-Type' => 'text/html'}, ['Not Found']]
    end
  end
end

# Run the app
app = RubyRoutesApp.new(router)
Rack::Handler::WEBrick.run app, Port: 9292
```

## API Reference

### RubyRoutes.draw(&block)

Creates a new router instance and yields to the block for route definition.

### HTTP Methods

- `get(path, options = {})`
- `post(path, options = {})`
- `put(path, options = {})`
- `patch(path, options = {})`
- `delete(path, options = {})`
- `match(path, options = {})`

### Resource Methods

- `resources(name, options = {})` - Creates RESTful routes for a collection
- `resource(name, options = {})` - Creates RESTful routes for a singular resource

### Options

- `to: 'controller#action'` - Specifies controller and action
- `controller: 'name'` - Specifies controller name
- `action: 'name'` - Specifies action name
- `as: :name` - Names the route for path generation
- `via: :method` - Specifies HTTP method(s)
- `constraints: {}` - Adds route constraints
- `defaults: {}` - Sets default parameters

### RouteSet Methods

- `match(method, path)` - Matches a request to a route
- `generate_path(name, params = {})` - Generates path from named route
- `find_route(method, path)` - Finds a specific route
- `find_named_route(name)` - Finds a named route

## Examples

See the `examples/` directory for more detailed examples:

- `examples/basic_usage.rb` - Basic routing examples
- `examples/rack_integration.rb` - Full Rack application example

## Testing

Run the test suite:

```bash
bundle exec rspec
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -am 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Create a new Pull Request

## License

This gem is available as open source under the terms of the [MIT License](LICENSE).

## Acknowledgments

This gem was inspired by Rails routing and aims to provide a lightweight alternative for Ruby applications that need flexible routing without the full Rails framework.
