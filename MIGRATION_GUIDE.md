# Migration Guide: Proc Constraints to Secure Alternatives

This guide helps you migrate from deprecated Proc constraints to secure alternatives in Ruby Routes.

## Why Migrate?

Proc constraints pose significant security risks:
- **Code Execution**: Can run arbitrary code
- **Injection Attacks**: Vulnerable to malicious input
- **DoS Attacks**: Can cause infinite loops or resource exhaustion
- **Audit Difficulty**: Hard to analyze for security issues

## Migration Patterns

### 1. Numeric Validations

```ruby
# ❌ Before (Proc)
constraints: { id: ->(v) { v.to_i > 0 } }
constraints: { age: ->(v) { v.to_i.between?(18, 120) } }
constraints: { price: ->(v) { v.to_f >= 0.01 } }

# ✅ After (Hash constraints)
constraints: { id: { range: 1..Float::INFINITY } }
constraints: { age: { range: 18..120 } }
constraints: { price: { range: 0.01..Float::INFINITY } }
```

### 2. String Length Validations

```ruby
# ❌ Before (Proc)
constraints: { username: ->(v) { v.length >= 3 } }
constraints: { title: ->(v) { v.length.between?(5, 100) } }
constraints: { code: ->(v) { v.length == 6 } }

# ✅ After (Hash constraints)
constraints: { username: { min_length: 3 } }
constraints: { title: { min_length: 5, max_length: 100 } }
constraints: { code: { min_length: 6, max_length: 6 } }
```

### 3. Whitelist/Blacklist Validations

```ruby
# ❌ Before (Proc)
constraints: { status: ->(v) { %w[active inactive pending].include?(v) } }
constraints: { role: ->(v) { !%w[admin superuser].include?(v) } }

# ✅ After (Hash constraints)
constraints: { status: { in: %w[active inactive pending] } }
constraints: { role: { not_in: %w[admin superuser] } }
```

### 4. Format Validations

```ruby
# ❌ Before (Proc)
constraints: { email: ->(v) { v.match?(/\A[^@]+@[^@]+\.[^@]+\z/) } }
constraints: { slug: ->(v) { v.match?(/\A[a-z0-9-]+\z/) } }
constraints: { uuid: ->(v) { v.match?(/\A[0-9a-f-]{36}\z/i) } }

# ✅ After (Built-in types)
constraints: { email: :email }
constraints: { slug: :slug }
constraints: { uuid: :uuid }

# ✅ Or hash constraints for custom patterns
constraints: { 
  custom_id: { format: /\A[A-Z]{2}\d{6}\z/ }
}
```

### 5. Complex Validations

```ruby
# ❌ Before (Proc)
constraints: { 
  username: ->(v) { 
    v.length >= 3 && 
    v.length <= 20 && 
    v.match?(/\A[a-zA-Z0-9_]+\z/) &&
    !%w[admin root].include?(v)
  }
}

# ✅ After (Combined hash constraints)
constraints: { 
  username: {
    min_length: 3,
    max_length: 20,
    format: /\A[a-zA-Z0-9_]+\z/,
    not_in: %w[admin root]
  }
}
```

## Step-by-Step Migration Process

### Step 1: Identify Proc Constraints

Search your codebase for Proc constraints:

```bash
# Find Proc constraints in your routes
grep -r "constraints.*->" app/
grep -r "constraints.*proc" app/
grep -r "constraints.*lambda" app/
```

### Step 2: Analyze Each Constraint

For each Proc constraint, determine what it's validating:
- Numeric ranges?
- String length?
- Format patterns?
- Allowed/forbidden values?

### Step 3: Choose Secure Alternative

Use this decision tree:

```
Is it validating...
├── Email format? → Use :email
├── UUID format? → Use :uuid  
├── Slug format? → Use :slug
├── Integer format? → Use :int
├── Alphabetic only? → Use :alpha
├── Alphanumeric only? → Use :alphanumeric
├── Numeric range? → Use { range: min..max }
├── String length? → Use { min_length: X, max_length: Y }
├── Allowed values? → Use { in: [...] }
├── Forbidden values? → Use { not_in: [...] }
├── Custom pattern? → Use { format: /regex/ }
└── Multiple conditions? → Combine hash options
```

### Step 4: Test Migration

```ruby
# Create a test to verify behavior matches
RSpec.describe "Constraint Migration" do
  it "maintains same validation behavior" do
    # Old constraint (for reference)
    old_constraint = ->(v) { v.to_i.between?(1, 100) }
    
    # New constraint
    route = RubyRoutes::RadixTree.new('/test/:num', to: 'test#show',
                                     constraints: { num: { range: 1..100 } })
    
    # Test valid values
    expect(route.extract_params('/test/50')['num']).to eq('50')
    
    # Test invalid values
    expect { route.extract_params('/test/150') }
      .to raise_error(RubyRoutes::ConstraintViolation)
  end
end
```

### Step 5: Deploy with Monitoring

1. Deploy the changes
2. Monitor for `ConstraintViolation` exceptions
3. Check logs for any unexpected behavior
4. Verify performance hasn't degraded

## Common Migration Examples

### E-commerce Application

```ruby
# ❌ Before
routes.draw do
  get '/products/:id', to: 'products#show',
      constraints: { id: ->(v) { v.to_i > 0 } }
  
  get '/categories/:slug', to: 'categories#show',
      constraints: { slug: ->(v) { v.match?(/\A[a-z0-9-]+\z/) } }
  
  get '/users/:email', to: 'users#show',
      constraints: { email: ->(v) { v.include?('@') } }
end

# ✅ After
routes.draw do
  get '/products/:id', to: 'products#show',
      constraints: { id: :int }
  
  get '/categories/:slug', to: 'categories#show',
      constraints: { slug: :slug }
  
  get '/users/:email', to: 'users#show',
      constraints: { email: :email }
end
```

### API Application

```ruby
# ❌ Before
routes.draw do
  namespace :api do
    get '/:version/users/:id', to: 'users#show',
        constraints: { 
          version: ->(v) { %w[v1 v2 v3].include?(v) },
          id: ->(v) { v.to_i.between?(1, 999999) }
        }
  end
end

# ✅ After  
routes.draw do
  namespace :api do
    get '/:version/users/:id', to: 'users#show',
        constraints: { 
          version: { in: %w[v1 v2 v3] },
          id: { range: 1..999999 }
        }
  end
end
```

## Troubleshooting

### Issue: Complex Logic in Proc

If your Proc has complex business logic:

```ruby
# ❌ Complex Proc
constraints: { 
  code: ->(v) { 
    return false unless v.length == 8
    return false unless v[0..1].match?(/[A-Z]{2}/)
    return false unless v[2..7].match?(/\d{6}/)
    !FORBIDDEN_PREFIXES.include?(v[0..1])
  }
}
```

**Solution**: Break it down into multiple hash constraints:

```ruby
# ✅ Multiple hash constraints
constraints: { 
  code: {
    min_length: 8,
    max_length: 8,
    format: /\A[A-Z]{2}\d{6}\z/,
    not_in: FORBIDDEN_CODES
  }
}
```

### Issue: Dynamic Constraints

If your Proc uses dynamic data:

```ruby
# ❌ Dynamic Proc
constraints: { 
  user_id: ->(v) { User.exists?(id: v.to_i) }
}
```

**Solution**: Move validation to controller:

```ruby
# ✅ Controller validation
constraints: { user_id: :int }

# In controller:
def show
  @user = User.find(params[:user_id])
rescue ActiveRecord::RecordNotFound
  render_not_found
end
```

## Performance Benefits

After migration, you'll see:

- **Faster routing**: Built-in constraints are highly optimized
- **Better security**: No code execution risks
- **Easier debugging**: Clear constraint definitions
- **Better caching**: Constraints can be cached more effectively

## Getting Help

If you encounter issues during migration:

1. Check the [Constraints Documentation](CONSTRAINTS.md)
2. Review common patterns above
3. Create tests to verify behavior
4. Consider moving complex logic to controllers

Remember: The goal is to maintain the same validation behavior while eliminating security risks.
