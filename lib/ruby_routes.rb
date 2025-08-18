require_relative "ruby_routes/version"
require_relative "ruby_routes/string_extensions"
require_relative "ruby_routes/route"
require_relative "ruby_routes/route_set"
require_relative "ruby_routes/url_helpers"
require_relative "ruby_routes/router"
require_relative "ruby_routes/radix_tree"
require_relative "ruby_routes/node"

module RubyRoutes
  class Error < StandardError; end
  class RouteNotFound < Error; end
  class InvalidRoute < Error; end
  class ConstraintViolation < Error; end

  # Create a new router instance
  def self.new(&block)
    RubyRoutes::Router.new(&block)
  end

  # Define the routes using a block
  def self.draw(&block)
    RubyRoutes::Router.new(&block)
  end
end
