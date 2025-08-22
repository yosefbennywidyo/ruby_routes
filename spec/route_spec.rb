require 'spec_helper'

RSpec.describe RubyRoutes::Route do
  describe '#initialize' do
    it 'creates a route with basic options' do
      route = RubyRoutes::Route.new('/users', to: 'users#index')
      expect(route.path).to eq('/users')
      expect(route.methods).to eq(['GET'])
      expect(route.controller).to eq('users')
      expect(route.action).to eq('index')
    end

    it 'normalizes paths' do
      route = RubyRoutes::RadixTree.new('users', to: 'users#index')
      expect(route.path).to eq('/users')

      route = RubyRoutes::RadixTree.new('/users/', to: 'users#index')
      expect(route.path).to eq('/users')
    end

    it 'accepts custom HTTP methods' do
      route = RubyRoutes::RadixTree.new('/users', via: :post, to: 'users#create')
      expect(route.methods).to eq(['POST'])

      route = RubyRoutes::RadixTree.new('/users', via: [:get, :post], to: 'users#handle')
      expect(route.methods).to eq(['GET', 'POST'])
    end

    it 'extracts action from controller#action format' do
      route = RubyRoutes::RadixTree.new('/users', to: 'users#index')
      expect(route.action).to eq('index')
    end

    it 'accepts separate controller and action' do
      route = RubyRoutes::RadixTree.new('/users', controller: 'users', action: 'index')
      expect(route.controller).to eq('users')
      expect(route.action).to eq('index')
    end

    it 'raises error without controller' do
      expect { RubyRoutes::RadixTree.new('/users', action: 'index') }.to raise_error(RubyRoutes::InvalidRoute)
    end

    it 'raises error without action' do
      expect { RubyRoutes::RadixTree.new('/users', controller: 'users') }.to raise_error(RubyRoutes::InvalidRoute)
    end
  end

  let(:route) { described_class.new('/users/:id', to: 'users#show', via: [:get, :head]) }

  describe '#query_params' do
    it 'returns query params as a hash' do
      params = route.query_params('/users/123?foo=bar&baz=qux')
      expect(params).to eq({'foo' => 'bar', 'baz' => 'qux'})
    end

    it 'returns empty hash if no query string' do
      params = route.query_params('/users/123')
      expect(params).to eq({})
    end
  end

  describe "#query_params_fast" do
    it "returns empty hash for empty query string" do
      route = RubyRoutes::Route.new('/users/:id', to: 'users#show')

      # Test with an empty query string (question mark with nothing after it)
      result = route.send(:query_params_fast, '/users/123?')

      expect(result).to eq({})
      expect(result).to be_empty
      expect(result).to be_frozen

      # Also test with multiple question marks but empty content
      result = route.send(:query_params_fast, '/users/123???')
      expect(result).to eq({})
    end

    it "uses query cache for repeated queries" do
      route = RubyRoutes::Route.new('/users', to: 'users#index')

      # Mock the SmallLru cache methods
      query_cache = instance_double(RubyRoutes::Route::SmallLru)
      allow(route).to receive(:instance_variable_get).with(:@query_cache).and_return(query_cache)

      # First call - cache miss
      allow(query_cache).to receive(:get).with("name=john&age=30").and_return(nil)
      allow(query_cache).to receive(:set)
      allow(Rack::Utils).to receive(:parse_query).and_return({"name" => "john", "age" => "30"})

      result1 = route.send(:query_params_fast, "/users?name=john&age=30")
      expect(result1).to eq({"name" => "john", "age" => "30"})
      expect(Rack::Utils).to have_received(:parse_query)

      # Second call - cache hit
      allow(query_cache).to receive(:get).with("name=john&age=30").and_return({"name" => "john", "age" => "30"})
      allow(Rack::Utils).to receive(:parse_query).and_raise("Should not be called")

      result2 = route.send(:query_params_fast, "/users?name=john&age=30")
      expect(result2).to eq({"name" => "john", "age" => "30"})
    end

    it "uses cached query params on repeated calls" do
      route = RubyRoutes::Route.new('/users', to: 'users#index')

      # First call populates cache
      first_result = route.send(:query_params_fast, "/users?name=john")

      # Second call should use cache
      # Fix: Stub the module directly, not with allow_any_instance_of
      allow(Rack::Utils).to receive(:parse_query).and_raise("Should use cache")
      second_result = route.send(:query_params_fast, "/users?name=john")

      expect(second_result).to eq(first_result)
    end
  end

  describe '#normalize_method' do
    it 'returns HEAD for :head symbol' do
      expect(route.send(:normalize_method, :head)).to eq('HEAD')
    end

    it 'returns uppercase string for string input' do
      expect(route.send(:normalize_method, 'post')).to eq('POST')
    end
  end

  describe '#build_params_hash' do
    it 'merges parsed_qp into result' do
      path_params = {'id' => '42'}
      parsed_qp = {'foo' => 'bar'}
      result = route.send(:build_params_hash, path_params, '/users/42?foo=bar', parsed_qp)
      expect(result['id']).to eq('42')
      expect(result['foo']).to eq('bar')
    end
  end

  describe '#get_thread_local_hash and #return_hash_to_pool' do
    it 'returns a cleared hash from the pool' do
      # Put a hash in the pool
      Thread.current[:ruby_routes_hash_pool] = [{}]
      hash = route.send(:get_thread_local_hash)
      hash['foo'] = 'bar'
      route.send(:return_hash_to_pool, hash)
      # Next get should return a cleared hash
      next_hash = route.send(:get_thread_local_hash)
      expect(next_hash).to eq({})
    end

    it 'creates a new hash if pool is empty' do
      Thread.current[:ruby_routes_hash_pool] = []
      hash = route.send(:get_thread_local_hash)
      expect(hash).to eq({})
    end
  end

  describe '#match?' do
    let(:route) { RubyRoutes::RadixTree.new('/users/:id', to: 'users#show') }

    it 'matches correct path and method' do
      expect(route.match?('GET', '/users/123')).to be true
    end

    it 'does not match wrong method' do
      expect(route.match?('POST', '/users/123')).to be false
    end

    it 'does not match wrong path' do
      expect(route.match?('GET', '/users')).to be false
      expect(route.match?('GET', '/users/123/edit')).to be false
    end

    it 'matches with multiple HTTP methods' do
      route = RubyRoutes::RadixTree.new('/users/:id', via: [:get, :put], to: 'users#show')
      expect(route.match?('GET', '/users/123')).to be true
      expect(route.match?('PUT', '/users/123')).to be true
      expect(route.match?('POST', '/users/123')).to be false
    end

    it 'returns true for matching method and path' do
      expect(route.match?('GET', '/users/123')).to be true
    end

    it 'returns false for non-matching method' do
      expect(route.match?('POST', '/foo/123')).to be false
    end

    it 'returns false for non-matching path' do
      expect(route.match?('GET', '/bar/123')).to be false
    end
  end

  describe '#extract_params' do
    let(:route) { RubyRoutes::RadixTree.new('/users/:id/posts/:post_id', to: 'posts#show') }

    it 'extracts path parameters' do
      params = route.extract_params('/users/123/posts/456')
      expect(params).to eq({ 'id' => '123', 'post_id' => '456' })
    end

    it 'returns empty hash for non-matching path' do
      params = route.extract_params('/users/123')
      expect(params).to eq({})
    end

    it 'includes defaults' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', defaults: { format: 'html' })
      params = route.extract_params('/users/123')
      expect(params).to eq({ 'id' => '123', 'format' => 'html' })
    end

    it 'extracts query params' do
      params = route.extract_params('/users/789/posts/456?extra=1')
      expect(params['id']).to eq('789')
      expect(params['extra']).to eq('1')
    end

    it 'merges defaults' do
      route_with_defaults = described_class.new('/foo/:id', to: 'foo#show', via: :get, defaults: { 'id' => 'default' })
      params = route_with_defaults.extract_params('/foo/default')
      expect(params['id']).to eq('default')
    end
  end

  describe '#named?' do
    it 'returns true for named routes' do
      route = RubyRoutes::RadixTree.new('/users', as: :users, to: 'users#index')
      expect(route.named?).to be true
    end

    it 'returns false for unnamed routes' do
      route = RubyRoutes::RadixTree.new('/users', to: 'users#index')
      expect(route.named?).to be false
    end
  end

  describe '#resource?' do
    it 'identifies resource routes' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show')
      expect(route.resource?).to be true
    end

    it 'identifies non-resource routes' do
      route = RubyRoutes::RadixTree.new('/users', to: 'users#index')
      expect(route.resource?).to be false
    end
  end

  describe '#collection?' do
    it 'identifies collection routes' do
      route = RubyRoutes::RadixTree.new('/users', to: 'users#index')
      expect(route.collection?).to be true
    end

    it 'identifies non-collection routes' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show')
      expect(route.collection?).to be false
    end
  end

  describe 'constraint validation' do
    it 'validates routes with constraints' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', constraints: { id: /\d+/ })

      expect(route.constraints[:id]).to eq(/\d+/)
    end
  end

  describe 'method normalization' do
    it 'normalizes HTTP methods to uppercase' do
      route = RubyRoutes::RadixTree.new('/users', via: [:get, :post], to: 'users#index')

      expect(route.methods).to include('GET')
      expect(route.methods).to include('POST')
    end

    it 'handles string methods' do
      route = RubyRoutes::RadixTree.new('/users', via: 'patch', to: 'users#update')

      expect(route.methods).to include('PATCH')
    end
  end

  describe '#parse_query_params' do
    it 'handles empty query string' do
      route = RubyRoutes::RadixTree.new('/search', to: 'search#index')
      params = route.parse_query_params('/search')

      expect(params).to be_empty
    end
  end

  describe '#generate_path' do
    let(:route) { described_class.new('/foo/:id', to: 'foo#show', via: :get) }

    it 'generates path with params' do
      expect(route.generate_path(id: '42')).to eq('/foo/42')
    end

    it 'raises error if required param missing' do
      expect { route.generate_path }.to raise_error(RubyRoutes::RouteNotFound)
    end

    it 'raises error if required param is nil' do
      expect { route.generate_path(id: nil) }.to raise_error(RubyRoutes::RouteNotFound)
    end
  end

  describe 'path generation edge cases' do
    it 'returns root path for root route' do
      route = RubyRoutes::RadixTree.new('/', to: 'home#index', as: :root)
      path = route.generate_path

      expect(path).to eq('/')
    end

    it 'uses static path for routes without parameters' do
      route = RubyRoutes::RadixTree.new('/about', to: 'pages#about', as: :about)
      path = route.generate_path

      expect(path).to eq('/about')
    end

    it 'raises error for missing required parameters' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', as: :user)

      expect {
        route.generate_path
      }.to raise_error(RubyRoutes::RouteNotFound, /Missing params: id/)
    end

    it 'raises error for nil required parameters' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', as: :user)

      expect {
        route.generate_path(id: nil)
      }.to raise_error(RubyRoutes::RouteNotFound, /Missing or nil params: id/)
    end

    it 'caches generated paths for performance' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', as: :user)

      # First call
      path1 = route.generate_path(id: '123')

      # Second call should use cache
      path2 = route.generate_path(id: '123')

      expect(path1).to eq(path2)
      expect(path1).to eq('/users/123')
    end

    it 'handles complex parameter combinations' do
      route = RubyRoutes::RadixTree.new('/posts/:post_id/comments/:id',
                                        to: 'comments#show',
                                        as: :post_comment)

      path = route.generate_path(post_id: '456', id: '789')
      expect(path).to eq('/posts/456/comments/789')
    end

    it 'handles extra parameters' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', as: :user)

      path = route.generate_path(id: '123', format: 'json')
      expect(path).to include('/users/123')
    end
  end

  describe 'parameter extraction edge cases' do
    it 'handles routes with no parameters' do
      route = RubyRoutes::RadixTree.new('/about', to: 'pages#about')
      params = route.extract_params('/about')

      expect(params).to be_a(Hash)
      expect(params).to be_empty
    end

    it 'includes default parameters' do
      route = RubyRoutes::RadixTree.new('/posts', to: 'posts#index', defaults: { format: 'html' })
      params = route.extract_params('/posts')

      expect(params['format']).to eq('html')
    end

    it 'handles wildcard parameters' do
      route = RubyRoutes::RadixTree.new('/files/*path', to: 'files#show')
      params = route.extract_params('/files/docs/readme.txt')

      expect(params).to eq({ 'path' => 'docs/readme.txt' })
    end

    it 'handles wildcard with single segment' do
      route = RubyRoutes::RadixTree.new('/uploads/*file', to: 'uploads#show')
      params = route.extract_params('/uploads/image.jpg')

      expect(params).to eq({ 'file' => 'image.jpg' })
    end

    it 'handles wildcard with deep nested path' do
      route = RubyRoutes::RadixTree.new('/assets/*resource', to: 'assets#show')
      params = route.extract_params('/assets/css/components/buttons/primary.css')

      expect(params).to eq({ 'resource' => 'css/components/buttons/primary.css' })
    end

    it 'handles wildcard with custom parameter name' do
      route = RubyRoutes::RadixTree.new('/api/v1/*endpoint', to: 'api#proxy')
      params = route.extract_params('/api/v1/users/123/profile')

      expect(params).to eq({ 'endpoint' => 'users/123/profile' })
    end

    it 'rejects wildcard routes with insufficient path segments' do
      route = RubyRoutes::RadixTree.new('/files/static/*path', to: 'files#show')
      params = route.extract_params('/files')  # Missing 'static' and wildcard parts

      # extract_params returns EMPTY_HASH when extract_path_params_fast returns nil
      expect(params).to eq({})
    end

    it 'handles multiple dynamic segments' do
      route = RubyRoutes::RadixTree.new('/users/:user_id/posts/:id', to: 'posts#show')
      params = route.extract_params('/users/123/posts/456')

      expect(params['user_id']).to eq('123')
      expect(params['id']).to eq('456')
    end
  end

  describe 'constraint validation edge cases' do
    it 'stores constraints correctly' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', constraints: { id: /\d+/ })

      expect(route.constraints[:id]).to eq(/\d+/)
    end

    it 'handles multiple constraints' do
      route = RubyRoutes::RadixTree.new('/posts/:year/:month',
                                        to: 'posts#archive',
                                        constraints: {
                                          year: /\d{4}/,
                                          month: /\d{1,2}/
                                        })

      expect(route.constraints[:year]).to eq(/\d{4}/)
      expect(route.constraints[:month]).to eq(/\d{1,2}/)
    end
  end

  describe 'route validation' do
    it 'raises error for invalid route without controller or action' do
      expect {
        RubyRoutes::RadixTree.new('/invalid', {})
      }.to raise_error(RubyRoutes::InvalidRoute)
    end

    it 'accepts route with controller option' do
      expect {
        RubyRoutes::RadixTree.new('/valid', controller: 'pages', action: 'show')
      }.not_to raise_error
    end

    it 'accepts route with to option' do
      expect {
        RubyRoutes::RadixTree.new('/valid', to: 'pages#show')
      }.not_to raise_error
    end
  end

  describe 'performance optimizations' do
    it 'pre-compiles route data during initialization' do
      route = RubyRoutes::RadixTree.new('/users/:id/posts/:post_id', to: 'posts#show')

      # These should be pre-compiled
      expect(route.instance_variable_get(:@required_params)).not_to be_empty
      expect(route.instance_variable_get(:@required_params_set)).not_to be_empty
    end

    it 'uses frozen method sets for fast lookup' do
      route = RubyRoutes::RadixTree.new('/users', via: [:get, :post], to: 'users#index')
      methods_set = route.instance_variable_get(:@methods_set)

      expect(methods_set).to be_frozen
      expect(methods_set).to include('GET', 'POST')
    end

    it 'caches path generation results' do
      route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', as: :user)

      # Generate path multiple times with same params
      5.times { route.generate_path(id: '123') }

      # Cache should have entries (we can't directly test cache hits without exposing internals)
      cache = route.instance_variable_get(:@gen_cache)
      expect(cache).not_to be_nil
    end
  end

  # Test for line 279: fallback for older Ruby versions without transform_keys
  describe "params without transform_keys" do
    it "handles params without transform_keys method" do
      route = RubyRoutes::Route.new('/users/:id', to: 'users#show')

      # Create an object that behaves like a hash but doesn't have transform_keys
      params = Object.new
      def params.respond_to?(method)
        method != :transform_keys
      end

      # Define method_missing to handle calls to key? and []
      def params.method_missing(method, *args)
        if method == :key? || method == :has_key?
          key = args.first
          key.to_s == 'id' || key.to_sym == :id
        elsif method == :[]
          key = args.first
          if key.to_s == 'id' || key.to_sym == :id
            '123'
          else
            nil
          end
        else
          super
        end
      end

      def params.each
        yield :id, '123'
      end

      def params.empty?
        false
      end

      # The path should still be generated correctly
      expect(route.generate_path(params)).to eq('/users/123')
    end
  end

  # Test for line 317-319: handling splat segments in path generation
  describe "splat segments in path generation" do
    it "handles splat segments with different value types" do
      route = RubyRoutes::Route.new('/files/*path', to: 'files#show')

      # With string value
      expect(route.generate_path(path: 'docs/report.pdf')).to eq('/files/docs/report.pdf')

      # With array value (tests line 317 and format_splat_value with Array)
      expect(route.generate_path(path: ['docs', 'report.pdf'])).to eq('/files/docs/report.pdf')

      # With other value types (tests format_splat_value default case)
      expect(route.generate_path(path: 123)).to eq('/files/123')
    end
  end

  # Test for line 344-345: segment encoding with caching
  describe "segment encoding cache" do
    it "caches encoded segments" do
      route = RubyRoutes::Route.new('/users/:name', to: 'users#show')

      # Generate path with a value that needs encoding
      route.generate_path(name: 'John Doe')

      # Access the cache with send since it's private
      encoding_cache = route.send(:instance_variable_get, :@encoding_cache)

      # Cache should contain the encoded value
      expect(encoding_cache).to have_key('John Doe')
      expect(encoding_cache['John Doe']).to eq('John%20Doe')
    end
  end

  # Test for line 358: handling empty query strings
  describe "query parameter handling" do
    it "returns empty hash for empty query strings" do
      route = RubyRoutes::Route.new('/users', to: 'users#index')

      # Test with empty query string
      params = route.parse_query_params('/users?')
      expect(params).to eq({})

      # Also test with nil query string
      params = route.parse_query_params('/users')
      expect(params).to eq({})
    end
  end

  # Test for the format_splat_value method
  describe "#format_splat_value" do
    let(:route) { RubyRoutes::Route.new('/test', to: 'test#index') }

    it "formats string values by splitting and encoding segments" do
      # Use send to access private method
      result = route.send(:format_splat_value, "docs/report name.pdf")
      expect(result).to eq('docs/report%20name.pdf')
    end

    it "formats array values by encoding each element" do
      result = route.send(:format_splat_value, ["docs", "report name.pdf"])
      expect(result).to eq('docs/report%20name.pdf')
    end

    it "formats non-string/non-array values by converting to string" do
      result = route.send(:format_splat_value, 12345)
      expect(result).to eq('12345')
    end
  end

  describe "#encode_segment_fast" do
    it "initializes and uses encoding cache" do
      route = RubyRoutes::Route.new('/users/:name', to: 'users#show')

      # First, verify cache doesn't exist yet
      expect(route.instance_variable_get(:@encoding_cache)).to be_nil

      # Call the method which should initialize the cache
      result1 = route.send(:encode_segment_fast, "John Doe")

      # Verify cache was created
      cache = route.instance_variable_get(:@encoding_cache)
      expect(cache).to be_a(Hash)
      expect(cache).to include("John Doe" => "John%20Doe")

      # Call again with same value - should use cache
      allow(URI).to receive(:encode_www_form_component).and_raise("Should not be called")
      result2 = route.send(:encode_segment_fast, "John Doe")

      # Verify result is the same and URI.encode wasn't called
      expect(result2).to eq("John%20Doe")
    end

    it "initializes encoding cache on first use" do
      route = RubyRoutes::Route.new('/users/:name', to: 'users#show')
      route.instance_variable_set(:@encoding_cache, nil) # Reset cache

      # Use a string that needs encoding (contains space or special chars)
      route.send(:encode_segment_fast, "test with space")

      expect(route.instance_variable_get(:@encoding_cache)).to be_a(Hash)
    end
  end

  describe "#validate_constraints_fast!" do
    context "with :int constraint" do
      let(:route) { RubyRoutes::Route.new('/users/:id', to: 'users#show', constraints: { id: :int }) }

      it "accepts valid integer values" do
        params = { "id" => "123" }
        expect { route.send(:validate_constraints_fast!, params) }.not_to raise_error
      end

      it "rejects non-integer values" do
        params = { "id" => "abc" }
        expect { route.send(:validate_constraints_fast!, params) }.to raise_error(RubyRoutes::ConstraintViolation)
      end

      it "rejects partial integer values" do
        params = { "id" => "123abc" }
        expect { route.send(:validate_constraints_fast!, params) }.to raise_error(RubyRoutes::ConstraintViolation)
      end

      it "handles empty values" do
        params = { "id" => "" }
        expect { route.send(:validate_constraints_fast!, params) }.to raise_error(RubyRoutes::ConstraintViolation)
      end
    end
  end

  it "validates integer constraints" do
    route = RubyRoutes::Route.new('/users/:id', to: 'users#show', constraints: { id: :int })

    # Valid integer
    expect { route.send(:validate_constraints_fast!, {"id" => "123"}) }.not_to raise_error

    # Invalid integer
    expect { route.send(:validate_constraints_fast!, {"id" => "abc"}) }.to raise_error(RubyRoutes::ConstraintViolation)
  end

  describe "Private method test coverage" do
    describe "#join_path_parts" do
      let(:route) { RubyRoutes::Route.new('/test', to: 'test#index') }

      it "joins array elements with slashes" do
        result = route.send(:join_path_parts, ['users', '123', 'posts'])
        expect(result).to eq('/users/123/posts')
      end

      it "handles empty array" do
        result = route.send(:join_path_parts, [])
        expect(result).to eq('/')
      end

      it "handles array with single element" do
        result = route.send(:join_path_parts, ['users'])
        expect(result).to eq('/users')
      end

      it "handles elements with special characters" do
        result = route.send(:join_path_parts, ['user files', 'report.pdf'])
        expect(result).to eq('/user files/report.pdf')
      end
    end

    describe "#validate_required_params" do
      it "returns empty arrays for empty required params" do
        route = RubyRoutes::Route.new('/about', to: 'pages#about')
        # Force empty required params for testing
        route.instance_variable_set(:@required_params, [])

        missing, nil_params = route.send(:validate_required_params, {id: '123'})
        expect(missing).to eq([])
        expect(nil_params).to eq([])
      end

      it "correctly identifies missing params" do
        route = RubyRoutes::Route.new('/users/:id', to: 'users#show')
        # @required_params should contain 'id'

        missing, nil_params = route.send(:validate_required_params, {name: 'John'})
        expect(missing).to include('id')
        expect(nil_params).to be_empty
      end

      it "correctly identifies nil params" do
        route = RubyRoutes::Route.new('/users/:id', to: 'users#show')

        missing, nil_params = route.send(:validate_required_params, {id: nil})
        expect(missing).to be_empty
        expect(nil_params).to include('id')
      end

      it "handles params with mixed string and symbol keys" do
        route = RubyRoutes::Route.new('/users/:id/posts/:post_id', to: 'posts#show')

        # Mix of string and symbol keys
        missing, nil_params = route.send(:validate_required_params, {'id' => '123', post_id: '456'})
        expect(missing).to be_empty
        expect(nil_params).to be_empty
      end
    end

    describe "validation caching" do
      let(:route) { RubyRoutes::Route.new('/users/:id', to: 'users#show') }

      it "caches validation results for frozen params" do
        # Create a frozen params hash
        params = {id: '123'}.freeze
        result = double('validation_result')

        # Access private validation cache
        validation_cache = route.instance_variable_get(:@validation_cache)
        expect(validation_cache).not_to be_nil

        # Cache should be empty initially
        expect(validation_cache.instance_variable_get(:@h)).to be_empty

        # Cache a result
        route.send(:cache_validation_result, params, result)

        # Verify it was cached
        cached_result = route.send(:get_cached_validation, params)
        expect(cached_result).to eq(result)
      end

      it "doesn't cache validation results for non-frozen params" do
        # Create a non-frozen params hash
        params = {id: '123'}
        result = double('validation_result')

        # Cache a result
        route.send(:cache_validation_result, params, result)

        # Verify it wasn't cached
        cached_result = route.send(:get_cached_validation, params)
        expect(cached_result).to be_nil
      end

      it "returns nil for get_cached_validation when validation cache is nil" do
        # Force nil validation cache
        route.instance_variable_set(:@validation_cache, nil)

        params = {id: '123'}.freeze
        result = route.send(:get_cached_validation, params)
        expect(result).to be_nil
      end
    end
  end
end
