# Ruby Routes

A high-performance, lightweight routing system for Ruby applications providing a Rails-like DSL for defining and matching HTTP routes.

## Features

- **🚀 High Performance**: Fast routing with 99.99% cache hit rate
- **🔄 Rails-like DSL**: Familiar syntax for defining routes
- **🛣️ RESTful Resources**: Automatic generation of RESTful routes
- **🔒 Secure Constraints**: Built-in security with comprehensive constraint system
- **🧩 Modular Design**: Nested resources, scopes, concerns, and namespaces
- **📝 Named Routes**: Generate paths from route names with automatic parameter handling
- **🧵 Thread Safety**: All caching and shared resources are thread-safe
- **🔍 Optimized Caching**: Smart caching strategies for route recognition and path generation
- **🪶 Lightweight**: Minimal dependencies for easy integration

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Basic Usage](#basic-usage)
- [Route Constraints](#route-constraints)
- [Route Matching](#route-matching)
- [Path Generation](#path-generation)
- [Integration with Rack](#integration-with-rack)
- [API Reference](#api-reference)
- [Performance](#performance)
- [Security](#security)
- [Documentation](#documentation)
- [Testing](#testing)
- [Contributing](#contributing)
- [License](#license)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'ruby_routes', '~> 2.3.0'
```

And then execute:

```bash
bundle install
```

Or install it yourself as:

```bash
gem install ruby_routes
```

## Quick Start

```ruby
require 'ruby_routes'

# Define routes
router = RubyRoutes.draw do
  root to: 'home#index'
  resources :users
  
  namespace :api do
    resources :products
  end
end

# Match a request
result = router.route_set.match('GET', '/users/123')
# => {controller: 'users', action: 'show', params: {'id' => '123'}, route: #<RubyRoutes::Route...>}

# Generate a path
path = router.route_set.generate_path(:user, id: 456)
# => "/users/456"
```

## Basic Usage

### Simple Routes

```ruby
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
end
```

This creates the following routes:
| HTTP Method | Path               | Controller#Action | Named Route       |
|-------------|--------------------|--------------------|-------------------|
| GET         | /users             | users#index        | users_path        |
| GET         | /users/new         | users#new          | new_user_path     |
| POST        | /users             | users#create       | users_path        |
| GET         | /users/:id         | users#show         | user_path         |
| GET         | /users/:id/edit    | users#edit         | edit_user_path    |
| PUT/PATCH   | /users/:id         | users#update       | user_path         |
| DELETE      | /users/:id         | users#destroy      | user_path         |

### Named Routes

```ruby
router = RubyRoutes.draw do
  get '/users', as: :users, to: 'users#index'
  get '/users/:id', as: :user, to: 'users#show'
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
```

Creates routes like:
- `GET /admin/users` → `admin/users#index`
- `GET /admin/users/:id` → `admin/users#show`

### Nested Resources

```ruby
router = RubyRoutes.draw do
  resources :categories do
    resources :products
  end
end
```

Creates routes like:
- `GET /categories/:category_id/products` → `products#index`
- `GET /categories/:category_id/products/:id` → `products#show`

### Scopes & Concerns

```ruby
router = RubyRoutes.draw do
  # Scopes
  scope defaults: { format: 'json' } do
    get '/api/users', to: 'api/users#index'
  end
  
  # Concerns (reusable route groups)
  concern :commentable do
    resources :comments
  end
  
  resources :posts, concerns: :commentable
  resources :articles, concerns: :commentable
end
```

### Method Chaining

```ruby
router = RubyRoutes.draw do
  get('/users', to: 'users#index')
    .post('/users', to: 'users#create')
    .put('/users/:id', to: 'users#update')
    .delete('/users/:id', to: 'users#destroy')
end
```

### Thread-safe Builder

```ruby
# Accumulate routes without mutating a live router
router = RubyRoutes::Router.build do
  resources :users
  namespace :admin do
    resources :posts
  end
end
# router is now finalized and thread-safe
```

## Route Constraints

Ruby Routes provides a powerful constraint system to validate route parameters before they reach your controllers.

### Built-in Constraint Types

```ruby
router = RubyRoutes.draw do
  # Integer validation
  get '/users/:id', to: 'users#show', constraints: { id: :int }
  
  # UUID validation
  get '/resources/:uuid', to: 'resources#show', constraints: { uuid: :uuid }
  
  # Email validation
  get '/users/:email', to: 'users#show', constraints: { email: :email }
  
  # Slug validation
  get '/posts/:slug', to: 'posts#show', constraints: { slug: :slug }
end
```

### Hash-based Constraints (Recommended)

```ruby
router = RubyRoutes.draw do
  # Length constraints
  get '/users/:username', to: 'users#show',
      constraints: { 
        username: { 
          min_length: 3, 
          max_length: 20,
          format: /\A[a-zA-Z0-9_]+\z/
        } 
      }

  # Allowed values (whitelist)
  get '/posts/:status', to: 'posts#show',
      constraints: { status: { in: %w[draft published archived] } }

  # Numeric ranges
  get '/products/:price', to: 'products#show',
      constraints: { price: { range: 1..10000 } }
end
```

### Regular Expression Constraints

```ruby
router = RubyRoutes.draw do
  # Custom regex pattern (with ReDoS protection)
  get '/products/:sku', to: 'products#show', 
      constraints: { sku: /\A[A-Z]{2}\d{4}\z/ }
end
```

⚠️ **Security Notice**: Proc constraints are deprecated due to security risks:

```ruby
# ❌ DEPRECATED - Security risk!
get '/users/:id', to: 'users#show',
    constraints: { id: ->(value) { value.to_i > 0 } }

# ✅ Use secure alternatives instead:
get '/users/:id', to: 'users#show',
    constraints: { id: { range: 1..Float::INFINITY } }
```

📚 For complete constraint documentation, see [CONSTRAINTS.md](CONSTRAINTS.md)  
🔄 For migration help, see [MIGRATION_GUIDE.md](MIGRATION_GUIDE.md)

## Route Matching

```ruby
router = RubyRoutes.draw do
  get '/users/:id', to: 'users#show'
  post '/users', to: 'users#create'
end

# Match a request
result = router.route_set.match('GET', '/users/123')
if result
  controller = result[:controller] # => "users"
  action = result[:action]         # => "show"
  params = result[:params]         # => {"id"=>"123"}
  route = result[:route]           # => #<RubyRoutes::Route...>
end
```

## Path Generation

```ruby
router = RubyRoutes.draw do
  get '/users/:id', as: :user, to: 'users#show'
  get '/posts/:id/comments/:comment_id', as: :post_comment, to: 'comments#show'
end

# Generate paths
path1 = router.route_set.generate_path(:user, id: '123')
# => "/users/123"

path2 = router.route_set.generate_path(:post_comment, id: '456', comment_id: '789')
# => "/posts/456/comments/789"
```

## Integration with Rack

```ruby
require 'rack'
require 'ruby_routes'

class RubyRoutesApp
  def initialize
    @router = RubyRoutes.draw do
      root to: 'home#index'
      resources :users
      get '/about', to: 'pages#about'
    end
  end
  
  def call(env)
    request_method = env['REQUEST_METHOD']
    request_path = env['PATH_INFO']
    
    result = @router.route_set.match(request_method, request_path)
    
    if result
      controller_name = result[:controller]
      action_name = result[:action]
      params = result[:params]
      
      # Your controller logic here
      [200, {'Content-Type' => 'text/html'}, ["#{controller_name}##{action_name} with #{params}"]]
    else
      [404, {'Content-Type' => 'text/html'}, ['Not Found']]
    end
  end
end

# Run the app
Rack::Handler::WEBrick.run RubyRoutesApp.new, Port: 9292
```

## API Reference

### RubyRoutes

- `RubyRoutes.draw(&block)` - Creates a new router and yields the block for route definition

### Router Methods

- `get(path, options = {})` - Define a GET route
- `post(path, options = {})` - Define a POST route
- `put(path, options = {})` - Define a PUT route
- `patch(path, options = {})` - Define a PATCH route
- `delete(path, options = {})` - Define a DELETE route
- `match(path, options = {})` - Define a route for multiple HTTP methods
- `root(options = {})` - Define a root route (/)
- `resources(name, options = {})` - Define RESTful resource routes
- `resource(name, options = {})` - Define singular RESTful resource routes
- `namespace(name, options = {})` - Group routes with a namespace
- `scope(options = {})` - Group routes with shared options
- `concern(name, &block)` - Define a reusable route concern
- `concerns(names)` - Use defined concerns in the current context
- `build(&block)` - Create a thread-safe, finalized router by accumulating routes in a builder

### RouteSet Methods

- `match(method, path)` - Match a request to a route
- `generate_path(name, params = {})` - Generate a path from a named route
- `find_route(method, path)` - Find a specific route
- `find_named_route(name)` - Find a named route by name

## Performance

Ruby Routes is optimized for high-performance applications:

- **Fast** routing
- **99.99% cache hit rate** for common access patterns
- **Low memory footprint** with bounded caches and object reuse
- **Zero memory leaks** in long-running applications

Performance metrics (from `benchmark/` directory):

| Operation | Operations/sec | Memory Usage |
|-----------|----------------|-------------|
| Route Matching | ~250,000/sec | Low |
| Path Generation | ~400,000/sec | Low |
| Static Routes | ~500,000/sec | Minimal |

## Security

Ruby Routes prioritizes security with these protections:

### 🔒 Security Features

- **ReDoS Protection**: Regular expression constraints have timeout protection
- **Secure Constraints**: Type-safe constraint system without code execution
- **Thread Safety**: All shared resources are thread-safe
- **Input Validation**: Comprehensive parameter validation

### ⚠️ Security Notice

**Proc constraints are deprecated due to security risks** and will be removed in a future version. They allow arbitrary code execution which can be exploited for:

- Code injection attacks
- Denial of service attacks
- System compromise

**Migration Required**: If you're using Proc constraints, please migrate to secure alternatives using our [Migration Guide](MIGRATION_GUIDE.md).

**Note**: RubyRoutes is a routing library and does not provide application-level security features such as XSS protection, CSRF protection, or authentication. These should be handled by your web framework or additional security middleware.

## Documentation

### Core Documentation

- **[CONSTRAINTS.md](CONSTRAINTS.md)** - Complete guide to route constraints and security
- **[MIGRATION_GUIDE.md](MIGRATION_GUIDE.md)** - Guide for migrating from deprecated Proc constraints
- **[USAGE.md](USAGE.md)** - Extended usage scenarios

### Examples

See the `examples/` directory for more detailed examples:

- `examples/basic_usage.rb` - Basic routing examples
- `examples/rack_integration.rb` - Full Rack application example
- `examples/constraints.rb` - Route constraint examples

## Testing

Ruby Routes has comprehensive test coverage:

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

## Thread-safe Build (Isolated Builder)

Use the builder to accumulate routes without mutating a live router:

```ruby
router = RubyRoutes::Router.build do
  resources :users
  namespace :admin do
    resources :posts
  end
end
# router is now finalized (immutable)
```

If you need manual steps:

```ruby
builder = RubyRoutes::Router::Builder.new do
  get '/health', to: 'system#health'
end
router = builder.build  # finalized
```

## Fluent Method Chaining

For a more concise style, the routing DSL supports method chaining:

```ruby
router = RubyRoutes.draw do
  get('/users', to: 'users#index')
    .post('/users', to: 'users#create')
    .put('/users/:id', to: 'users#update')
    .delete('/users/:id', to: 'users#destroy')
    .resources(:posts)
end
```

