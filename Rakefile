require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

task default: :spec

# Build the gem
task :build do
  system "gem build ruby_routes.gemspec"
end

# Install the gem locally
task :install do
  system "gem install ruby_routes-*.gem"
end

# Clean up build artifacts
task :clean do
  FileUtils.rm_f Dir["*.gem"]
end

# Run examples
task :examples do
  puts "Running basic usage example..."
  system "ruby examples/basic_usage.rb"
  
  puts "\nRunning Rack integration example..."
  puts "This will start a web server. Press Ctrl+C to stop."
  system "ruby examples/rack_integration.rb"
end
