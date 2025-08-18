require 'simplecov'

SimpleCov.start do
  add_filter '/spec/'
  add_filter '/examples/'
  add_filter '/benchmark/'
  
  add_group 'Core', 'lib/ruby_routes.rb'
  add_group 'Router', 'lib/ruby_routes/router.rb'
  add_group 'Routes', ['lib/ruby_routes/route.rb', 'lib/ruby_routes/route_set.rb']
  add_group 'Tree & Segments', ['lib/ruby_routes/radix_tree.rb', 'lib/ruby_routes/node.rb', 'lib/ruby_routes/segments']
  add_group 'Utilities', ['lib/ruby_routes/url_helpers.rb', 'lib/ruby_routes/string_extensions.rb']
  
  minimum_coverage 70
end

require 'rspec'
require 'ruby_routes'

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.warnings = true

  if config.files_to_run.one?
    config.default_formatter = "doc"
  end

  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed
end
