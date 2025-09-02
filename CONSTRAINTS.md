# Route Constraints

Ruby Routes provides a comprehensive constraint system to validate route parameters before they reach your controllers.

## Built-in Constraint Types

```ruby
router = RubyRoutes.draw do
  # Integer validation
  get '/users/:id', to: 'users#show', constraints: { id: :int }
  
  # UUID validation  
  get '/resources/:uuid', to: 'resources#show', constraints: { uuid: :uuid }
  
  # Email validation
  get '/users/:email', to: 'users#show', constraints: { email: :email }
  
  # Slug validation (lowercase letters, numbers, hyphens)
  get '/posts/:slug', to: 'posts#show', constraints: { slug: :slug }
  
  # Alphabetic characters only (allows uppercase)
  get '/categories/:name', to: 'categories#show', constraints: { name: :alpha }
  
  # Alphanumeric characters only (allows uppercase)
  get '/codes/:code', to: 'codes#show', constraints: { code: :alphanumeric }
end
```

## Regular Expression Constraints

```ruby
router = RubyRoutes.draw do
  # Custom regex pattern
  get '/products/:sku', to: 'products#show', 
        constraints: { sku: /\A[A-Z]{2}\d{4}\z/ }
end
```

### Hash-based Constraints (Recommended)

Hash constraints provide powerful validation options without security risks:

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

  # Forbidden values (blacklist)  
  get '/users/:username', to: 'users#show',
        constraints: { username: { not_in: %w[admin root system] } }

  # Numeric ranges
  get '/products/:price', to: 'products#show',
        constraints: { price: { range: 1..10000 } }

  # Multiple constraints
  get '/api/:version/users/:id', to: 'api/users#show',
        constraints: {
          version: { in: %w[v1 v2 v3] },
          id: { range: 1..999999, format: /\A\d+\z/ }
        }
end
```## Security Considerations

### ⚠️ Deprecated: Proc Constraints

**Proc constraints are deprecated due to security risks and will be removed in a future version.**

```ruby
# ❌ DEPRECATED - Security risk!
get '/users/:id', to: 'users#show',
      constraints: { id: ->(value) { value.to_i > 0 } }
```

**Why Proc constraints are dangerous:**

- Can execute arbitrary code
- Vulnerable to code injection attacks
- Can cause denial of service
- Difficult to audit and secure

### ✅ Secure Alternatives

Instead of Proc constraints, use:

```ruby
router = RubyRoutes.draw do
  # ✅ Use hash constraints with ranges
  get '/users/:id', to: 'users#show',
        constraints: { id: { range: 1..Float::INFINITY } }

  # ✅ Use regex patterns  
  get '/users/:id', to: 'users#show',
        constraints: { id: /\A[1-9]\d*\z/ }

  # ✅ Use built-in types
  get '/users/:id', to: 'users#show',
        constraints: { id: :int }
end
```

## Hash Constraint Options

| Option | Type | Description | Example |
|--------|------|-------------|---------|
| `min_length` | Integer | Minimum string length | `{ min_length: 3 }` |
| `max_length` | Integer | Maximum string length | `{ max_length: 50 }` |
| `format` | Regex | Must match pattern | `{ format: /\A[a-z]+\z/ }` |
| `in` | Array | Must be in list | `{ in: %w[red green blue] }` |
| `not_in` | Array | Must not be in list | `{ not_in: %w[admin root] }` |
| `range` | Range | Numeric value range | `{ range: 1..100 }` |

## Error Handling

When constraints fail, a `RubyRoutes::ConstraintViolation` exception is raised:

```ruby
router = RubyRoutes.draw do
  get '/users/:id', to: 'users#show', constraints: { id: :int }
end

begin
  result = router.route_set.match('GET', '/users/invalid')
  # Process result
rescue RubyRoutes::ConstraintViolation => e
  # Handle constraint violation
  puts e.message
end
```

## Migration from Proc Constraints

If you're currently using Proc constraints, here's how to migrate:

```ruby
# Old (deprecated)
constraints: { id: ->(v) { v.to_i > 0 } }
# New
constraints: { id: { range: 1..Float::INFINITY } }

# Old (deprecated)  
constraints: { status: ->(v) { %w[active inactive].include?(v) } }
# New
constraints: { status: { in: %w[active inactive] } }

# Old (deprecated)
constraints: { name: ->(v) { v.length >= 3 && v.match?(/\A[a-z]+\z/) } }
# New  
constraints: { name: { min_length: 3, format: /\A[a-z]+\z/ } }
```

## Performance

- Built-in constraints (`:int`, `:uuid`, etc.) are highly optimized
- Hash constraints are fast and secure
- Regex constraints have ReDoS protection with automatic timeouts (100ms)
- Proc constraints have timeout protection (50ms) but are deprecated
- All constraints are validated before reaching your application code
