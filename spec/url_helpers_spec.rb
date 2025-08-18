require 'spec_helper'

RSpec.describe RubyRoutes::UrlHelpers do
  let(:route_set) { RubyRoutes::RouteSet.new }
  
  # Create a test class that includes UrlHelpers
  let(:test_class) do
    Class.new do
      include RubyRoutes::UrlHelpers
      
      attr_reader :route_set
      
      def initialize(route_set)
        @route_set = route_set
      end
    end
  end
  
  let(:helper) { test_class.new(route_set) }

  before do
    # Add a named route for testing
    route = RubyRoutes::RadixTree.new('/users/:id', to: 'users#show', as: :user)
    route_set.add_route(route)
    
    # Add a simple route without parameters
    simple_route = RubyRoutes::RadixTree.new('/about', to: 'pages#about', as: :about)
    route_set.add_route(simple_route)
  end

  describe 'module inclusion' do
    it 'extends class with ClassMethods when included' do
      expect(test_class).to respond_to(:url_helpers)
      expect(test_class).to respond_to(:add_url_helper)
    end
  end

  describe 'ClassMethods' do
    describe '#url_helpers' do
      it 'returns a module for url helpers' do
        helpers_module = test_class.url_helpers
        expect(helpers_module).to be_a(Module)
      end

      it 'memoizes the url_helpers module' do
        helpers1 = test_class.url_helpers
        helpers2 = test_class.url_helpers
        expect(helpers1).to be(helpers2)
      end
    end

    describe '#add_url_helper' do
      it 'adds a method to the url_helpers module' do
        route = route_set.routes.first
        test_class.add_url_helper(:user_path, route)
        
        expect(test_class.url_helpers.instance_methods).to include(:user_path)
      end
    end
  end

  describe '#url_helpers' do
    it 'returns the class url_helpers module' do
      expect(helper.url_helpers).to eq(test_class.url_helpers)
    end
  end

  describe '#path_to' do
    it 'generates path for named route with parameters' do
      path = helper.path_to(:user, id: '123')
      expect(path).to eq('/users/123')
    end

    it 'generates path for named route without parameters' do
      path = helper.path_to(:about)
      expect(path).to eq('/about')
    end

    it 'raises error for non-existent route' do
      expect {
        helper.path_to(:nonexistent)
      }.to raise_error(RubyRoutes::RouteNotFound)
    end
  end

  describe '#url_to' do
    it 'generates full URL with localhost' do
      url = helper.url_to(:user, id: '123')
      expect(url).to eq('http://localhost/users/123')
    end

    it 'generates full URL for simple routes' do
      url = helper.url_to(:about)
      expect(url).to eq('http://localhost/about')
    end
  end

  describe '#link_to' do
    it 'generates HTML link with parameters' do
      link = helper.link_to(:user, 'View User', id: '123')
      expect(link).to eq('<a href="/users/123">View User</a>')
    end

    it 'generates HTML link without parameters' do
      link = helper.link_to(:about, 'About Us')
      expect(link).to eq('<a href="/about">About Us</a>')
    end

    it 'handles special characters in text' do
      link = helper.link_to(:about, 'About & Contact')
      expect(link).to eq('<a href="/about">About &amp; Contact</a>')
    end

    it 'escapes HTML to prevent XSS attacks' do
      malicious_text = '<script>alert("XSS")</script>'
      link = helper.link_to(:about, malicious_text)
      expect(link).to eq('<a href="/about">&lt;script&gt;alert(&quot;XSS&quot;)&lt;/script&gt;</a>')
    end

    it 'escapes HTML entities in text' do
      text_with_entities = 'Price: $100 < $200 & "special" offer'
      link = helper.link_to(:about, text_with_entities)
      expect(link).to eq('<a href="/about">Price: $100 &lt; $200 &amp; &quot;special&quot; offer</a>')
    end
  end

  describe '#button_to' do
    it 'generates form with POST method by default' do
      button = helper.button_to(:user, 'Delete User', id: '123')
      
      expect(button).to include('<form action="/users/123" method="post">')
      expect(button).not_to include('<input type="hidden" name="_method"')
      expect(button).to include('<button type="submit">Delete User</button>')
      expect(button).to include('</form>')
    end

    it 'generates form with PATCH method using POST + _method hidden field' do
      button = helper.button_to(:user, 'Update User', id: '123', method: :patch)
      
      expect(button).to include('<form action="/users/123" method="post">')
      expect(button).to include('<input type="hidden" name="_method" value="patch">')
      expect(button).to include('<button type="submit">Update User</button>')
    end

    it 'generates form with DELETE method using POST + _method hidden field' do
      button = helper.button_to(:user, 'Delete User', id: '123', method: :delete)
      
      expect(button).to include('<form action="/users/123" method="post">')
      expect(button).to include('<input type="hidden" name="_method" value="delete">')
      expect(button).to include('<button type="submit">Delete User</button>')
    end

    it 'generates form with PUT method using POST + _method hidden field' do
      button = helper.button_to(:user, 'Update User', id: '123', method: :put)
      
      expect(button).to include('<form action="/users/123" method="post">')
      expect(button).to include('<input type="hidden" name="_method" value="put">')
      expect(button).to include('<button type="submit">Update User</button>')
    end

    it 'generates form with GET method without hidden field' do
      button = helper.button_to(:user, 'View User', id: '123', method: :get)
      
      expect(button).to include('<form action="/users/123" method="get">')
      expect(button).not_to include('<input type="hidden"')
      expect(button).to include('<button type="submit">View User</button>')
    end

    it 'handles string methods correctly' do
      button = helper.button_to(:user, 'Update', id: '123', method: 'PATCH')
      
      expect(button).to include('<form action="/users/123" method="post">')
      expect(button).to include('<input type="hidden" name="_method" value="patch">')
    end

    it 'removes method from params when generating path' do
      # This tests that method is deleted from params before path generation
      button = helper.button_to(:user, 'Delete', id: '123', method: :delete)
      expect(button).to include('/users/123')
      expect(button).not_to include('method=delete') # Should not appear in URL
    end

    it 'does not mutate the original params hash' do
      original_params = { id: '123', method: :delete }
      original_params_copy = original_params.dup
      
      helper.button_to(:user, 'Delete', original_params)
      
      # Original params should remain unchanged
      expect(original_params).to eq(original_params_copy)
      expect(original_params[:method]).to eq(:delete)
    end

    it 'escapes HTML in button text to prevent XSS' do
      malicious_text = '<script>alert("XSS")</script>'
      button = helper.button_to(:user, malicious_text, id: '123')
      
      expect(button).to include('<button type="submit">&lt;script&gt;alert(&quot;XSS&quot;)&lt;/script&gt;</button>')
      expect(button).not_to include('<script>alert("XSS")</script>')
    end

    it 'escapes special characters in button text' do
      text_with_chars = 'Save & "Continue" < Next'
      button = helper.button_to(:user, text_with_chars, id: '123')
      
      expect(button).to include('<button type="submit">Save &amp; &quot;Continue&quot; &lt; Next</button>')
    end
  end

  describe 'security fixes' do
    it 'escapes HTML in href attributes to prevent attribute injection' do
      # Mock path_to to return a malicious path
      allow(helper).to receive(:path_to).and_return('"/><script>alert("XSS")</script><a href="')
      
      link = helper.link_to(:user, 'Click me')
      expect(link).to eq('<a href="&quot;/&gt;&lt;script&gt;alert(&quot;XSS&quot;)&lt;/script&gt;&lt;a href=&quot;">Click me</a>')
      expect(link).not_to include('<script>')
    end

    it 'escapes HTML in form action attributes' do
      allow(helper).to receive(:path_to).and_return('"/><script>alert("XSS")</script><form action="')
      
      button = helper.button_to(:user, 'Submit')
      expect(button).to include('action="&quot;/&gt;&lt;script&gt;alert(&quot;XSS&quot;)&lt;/script&gt;&lt;form action=&quot;"')
      expect(button).not_to include('<script>')
    end

    it 'escapes HTML in method values' do
      malicious_method = 'delete"><script>alert("XSS")</script><input value="'
      button = helper.button_to(:user, 'Delete', id: '123', method: malicious_method)
      
      # Should escape the malicious method value
      expect(button).to include('value="delete&quot;&gt;&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;&lt;input value=&quot;"')
      expect(button).not_to include('<script>')
      expect(button).not_to include('"><script>')
    end
  end

  describe '#redirect_to' do
    it 'generates redirect hash with status and location' do
      redirect = helper.redirect_to(:user, id: '123')
      
      expect(redirect).to eq({
        status: 302,
        location: '/users/123'
      })
    end

    it 'generates redirect for simple routes' do
      redirect = helper.redirect_to(:about)
      
      expect(redirect).to eq({
        status: 302,
        location: '/about'
      })
    end
  end

  describe 'integration with route_set' do
    it 'works with complex parameter combinations' do
      # Add a route with multiple parameters
      complex_route = RubyRoutes::RadixTree.new('/posts/:post_id/comments/:id', 
                                                to: 'comments#show', 
                                                as: :post_comment)
      route_set.add_route(complex_route)
      
      path = helper.path_to(:post_comment, post_id: '456', id: '789')
      expect(path).to eq('/posts/456/comments/789')
      
      url = helper.url_to(:post_comment, post_id: '456', id: '789')
      expect(url).to eq('http://localhost/posts/456/comments/789')
    end
  end
end
