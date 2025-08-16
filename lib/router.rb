require_relative "router/version"
require_relative "router/string_extensions"
require_relative "router/route"
require_relative "router/route_set"
require_relative "router/url_helpers"
require_relative "router/router"

module Router
  class Error < StandardError; end
  class RouteNotFound < Error; end
  class InvalidRoute < Error; end

  # Create a new router instance
  def self.new(&block)
    Router::RouterClass.new(&block)
  end

  # Define the routes using a block
  def self.draw(&block)
    Router::RouterClass.new(&block)
  end
end
