Gem::Specification.new do |spec|
  spec.name          = "ruby_routes"
  spec.version       = "0.2.0"
  spec.authors       = ["Yosef Benny Widyokarsono"]
  spec.email         = ["yosefbennywidyo@gmail.com"]
  spec.summary       = "A Rails-like routing system for Ruby"
  spec.description   = "A lightweight, flexible routing system that provides a Rails-like DSL for defining and matching HTTP routes"
  spec.homepage      = "https://github.com/yosefbennywidyo/ruby_routes"
  spec.license       = "MIT"

  spec.files         = Dir["lib/**/*", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]
  spec.required_ruby_version = ">= 3.4.2"

  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "simplecov", "~> 0.22"
end
