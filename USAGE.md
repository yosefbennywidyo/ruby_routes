# Ruby Routes - Possible Usage Scenarios

Ruby Routes is a flexible, high-performance routing library that can be used in various contexts beyond traditional web frameworks. Here are the key usage scenarios:

## 🌐 **Web Applications & APIs**

### **1. Lightweight Web Services**

```ruby
# Microservice with custom routing
require 'ruby_routes'
require 'rack'

router = RubyRoutes.draw do
  get '/health', to: 'health#check'
  get '/api/v1/users/:id', as: :user, to: 'users#show'
  post '/api/v1/users', as: :create_user, to: 'users#create'
  
  namespace :admin do
    resources :users
    resources :analytics
  end
end

# Generate URLs programmatically
user_path = router.route_set.generate_path(:user, id: 123)  # => "/api/v1/users/123"
create_user_path = router.route_set.generate_path(:create_user)  # => "/api/v1/users"

# Rack application
class MyApp
  def initialize(router)
    @router = router
  end
  
  def call(env)
    route = @router.route_set.match(env['REQUEST_METHOD'], env['PATH_INFO'])
    # Handle routing logic
  end
end
```

### **2. API Gateways**

```ruby
# Route requests to different microservices
router = RubyRoutes.draw do
  scope path: '/api/v1' do
    get '/users/*path', to: 'proxy#users_service'
    get '/orders/*path', to: 'proxy#orders_service'
    get '/payments/*path', to: 'proxy#payments_service'
  end
  
  # Rate limiting routes (rate limiting logic would be implemented in the proxy handler)
  get '/public/*path', to: 'proxy#public_api'
  get '/premium/*path', to: 'proxy#premium_api'
end
```

### **3. Custom Web Frameworks**

```ruby
# Build your own web framework
class MyFramework
  def initialize(&block)
    @router = RubyRoutes.draw(&block)
  end
  
  def call(env)
    route_info = @router.route_set.match(env['REQUEST_METHOD'], env['PATH_INFO'])
    return [404, {}, ['Not Found']] unless route_info
    
    controller_class = Object.const_get("#{route_info[:controller].capitalize}Controller")
    controller = controller_class.new
    response = controller.send(route_info[:action], route_info[:params])
    
    [200, {'Content-Type' => 'application/json'}, [response.to_json]]
  end
end

# Usage
app = MyFramework.new do
  resources :users
  resources :posts
end
```

## 🔧 **Non-Web Applications**

### **4. CLI Command Routing**

```ruby
# Route CLI commands to handlers
class CLIRouter
  def initialize
    @router = RubyRoutes.draw do
      get '/user/create', to: 'user#create'
      get '/user/list', to: 'user#list'
      get '/user/:id/show', to: 'user#show'
      get '/deploy/:environment', to: 'deploy#execute'
      get '/config/set/:key/:value', to: 'config#set'
    end
  end
  
  def route_command(command_parts)
    path = "/#{command_parts.join('/')}"
    route = @router.route_set.match('GET', path)
    
    if route
      handler_class = Object.const_get("#{route[:controller].capitalize}Handler")
      handler_class.new.send(route[:action], route[:params])
    else
      puts "Unknown command: #{command_parts.join(' ')}"
    end
  end
end

# Usage: ruby cli.rb user create --name John
cli = CLIRouter.new
cli.route_command(ARGV)
```

### **5. Message/Event Routing**

```ruby
# Route messages based on patterns
class MessageRouter
  def initialize
    @router = RubyRoutes.draw do
      get '/events/user/:action', to: 'user_events#handle'
      get '/events/order/:status', to: 'order_events#handle'
      get '/notifications/:type/:priority', to: 'notifications#send'
      get '/webhooks/:service/:event', to: 'webhooks#process'
    end
  end
  
  def route_message(message_type, data)
    route = @router.route_set.match('GET', "/#{message_type}")
    return unless route
    
    handler_class = Object.const_get("#{route[:controller].capitalize}")
    handler_class.new.send(route[:action], route[:params].merge(data))
  end
end

# Usage
router = MessageRouter.new
router.route_message('events/user/login', { user_id: 123, ip: '192.168.1.1' })
router.route_message('notifications/email/high', { recipient: 'admin@example.com' })
```

### **6. File/Resource Routing**

```ruby
# Route file operations based on patterns
class FileRouter
  def initialize
    @router = RubyRoutes.draw do
      get '/images/:size/:filename', to: 'images#resize'
      get '/documents/:type/:id', to: 'documents#serve'
      get '/cache/:namespace/:key', to: 'cache#get'
      post '/uploads/:category', to: 'uploads#store'
    end
  end
  
  def route_file_request(path)
    route = @router.route_set.match('GET', path)
    return nil unless route
    
    processor_class = Object.const_get("#{route[:controller].capitalize}Processor")
    processor_class.new.send(route[:action], route[:params])
  end
end

# Usage
router = FileRouter.new
router.route_file_request('/images/thumbnail/photo.jpg')
router.route_file_request('/documents/pdf/invoice-123')
```

## 🏗️ **Infrastructure & DevOps**

### **7. Load Balancer/Proxy Routing**

```ruby
# Intelligent request routing
class LoadBalancer
  def initialize
    @router = RubyRoutes.draw do
      # Route by service
      get '/api/users/*path', to: 'proxy#user_service'
      get '/api/orders/*path', to: 'proxy#order_service'
      
      # Route by region
      get '/eu/*path', to: 'proxy#eu_datacenter'
      get '/us/*path', to: 'proxy#us_datacenter'
      get '/asia/*path', to: 'proxy#asia_datacenter'
      
      # Route by version
      get '/v1/*path', to: 'proxy#legacy_api'
      get '/v2/*path', to: 'proxy#current_api'
      get '/beta/*path', to: 'proxy#beta_api'
    end
  end
  
  def route_request(request)
    path = request.path
    route = @router.route_set.match(request.method, path)
    
    if route
      target_server = determine_server(route[:controller], route[:params])
      proxy_to(target_server, request)
    else
      [404, {}, ['Service not found']]
    end
  end
end
```

### **8. Configuration Management**

```ruby
# Route configuration requests
class ConfigRouter
  def initialize
    @router = RubyRoutes.draw do
      get '/config/:service/:environment/:key', to: 'config#get'
      post '/config/:service/:environment/:key', to: 'config#set'
      get '/secrets/:environment/:service', to: 'secrets#retrieve'
      get '/feature-flags/:service/:flag', to: 'features#check'
    end
  end
  
  def handle_config_request(method, path, data = {})
    route = @router.route_set.match(method.upcase, path)
    return { error: 'Not found' } unless route
    
    ConfigHandler.new.send(route[:action], route[:params].merge(data))
  end
end
```

## 🎮 **Gaming & Real-time Applications**

### **9. Game Command Routing**

```ruby
# Route game commands
class GameRouter
  def initialize
    @router = RubyRoutes.draw do
      post '/player/:id/move/:direction', to: 'game#move_player'
      post '/player/:id/attack/:target', to: 'combat#attack'
      get '/world/:zone/:x/:y', to: 'world#get_tile'
      post '/chat/:channel', to: 'chat#send_message'
      get '/leaderboard/:category', to: 'stats#leaderboard'
    end
  end
  
  def route_command(player_id, command, params)
    path = "/player/#{player_id}/#{command.gsub(' ', '/')}"
    route = @router.route_set.match('POST', path)
    return puts("Unknown command: #{command}") unless route

    GameEngine.new.execute(
      route[:controller],
      route[:action],
      route[:params].merge(player_id: player_id, **(params || {}))
    )
  end
end
```

### **10. IoT Device Routing**

```ruby
# Route IoT device messages
class IoTRouter
  def initialize
    @router = RubyRoutes.draw do
      post '/devices/:device_id/sensors/:sensor_type', to: 'sensors#record'
      post '/devices/:device_id/commands/:command', to: 'devices#execute'
      get '/devices/:device_id/status', to: 'devices#status'
    end
  end

  def route_device_message(device_id, message_type, payload, method: 'POST')
    path = "/devices/#{device_id}/#{message_type}"
    route = @router.route_set.match(method, path)
    return { error: 'Unknown route' } unless route
    DeviceHandler.new.process(route[:action], route[:params], payload)
  end
end
```


## 🔍 **Specialized Use Cases**

### **11. URL Shortener Service**

```ruby
class URLShortener
  def initialize
    @router = RubyRoutes.draw do
      get '/:short_code', to: 'redirect#expand', constraints: { short_code: /[a-zA-Z0-9]{6}/ }
      post '/api/shorten', to: 'urls#create'
      get '/api/stats/:short_code', to: 'analytics#stats'
      get '/admin/urls', to: 'admin#list'
    end
  end
end
```

### **12. Content Management Routing**

```ruby
class CMSRouter
  def initialize
    @router = RubyRoutes.draw do
      get '/pages/*slug', to: 'pages#show'
      get '/blog/:year/:month/:slug', to: 'blog#show'
      get '/categories/:category/posts', to: 'posts#by_category'
      get '/tags/:tag', to: 'posts#by_tag'
      get '/sitemap.xml', to: 'sitemap#generate'
    end
  end
end
```

### **13. Multi-tenant Application Routing**

```ruby
class MultiTenantRouter
  def initialize
    @router = RubyRoutes.draw do
      # Subdomain-based routing
      get '/:tenant/dashboard', to: 'dashboard#show'
      get '/:tenant/api/v1/*path', to: 'api#proxy'
      get '/:tenant/admin/*path', to: 'admin#handle'
      
      # Path-based routing
      scope path: '/tenants/:tenant_id' do
        resources :users
        resources :projects
        resources :billing
      end
    end
  end
end
```

## 🚀 **Key Advantages for These Use Cases**

### **Performance Benefits:**

- **Fast routing** - Handles high-frequency routing decisions
- **99.99% cache hit rate** - Optimal for repeated patterns
- **Zero memory leaks** - Suitable for long-running processes

### **Security Features:**

- **Input validation** - Built-in constraint system with ReDoS protection
- **Thread safety** - Safe for concurrent applications
- **Secure constraints** - Type-safe constraint system without code execution

### **Flexibility:**

- **Pattern matching** - Complex routing patterns
- **Constraint system** - Validate parameters before processing
- **Named routes** - Generate URLs/paths programmatically

### **Ease of Use:**

- **Rails-like DSL** - Familiar syntax
- **Comprehensive documentation** - Easy to learn and implement
- **No dependencies** - Lightweight and portable

Ruby Routes transforms from a simple web routing library into a versatile pattern-matching and request-routing engine suitable for any application that needs to route requests, commands, messages, or data based on structured patterns.
