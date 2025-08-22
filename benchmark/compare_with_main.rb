#!/usr/bin/env ruby

# Performance comparison script for RadixTree and Node optimizations
# Uses the existing performance_optimized.rb to compare main vs current branch

require 'fileutils'

puts "Ruby Routes Performance Comparison"
puts "Using existing performance_optimized.rb benchmark"
puts "=" * 60

class PerformanceComparison
  def self.backup_current_files
    puts "📁 Backing up current optimized files..."
    FileUtils.mkdir_p('/tmp/performance_comparison')
    
    FileUtils.cp('/home/runner/work/ruby_routes/ruby_routes/lib/ruby_routes/radix_tree.rb', 
                 '/tmp/performance_comparison/radix_tree_optimized.rb')
    FileUtils.cp('/home/runner/work/ruby_routes/ruby_routes/lib/ruby_routes/node.rb', 
                 '/tmp/performance_comparison/node_optimized.rb')
    puts "✅ Current files backed up"
  end

  def self.restore_main_branch_files
    puts "🔄 Restoring main branch files..."
    
    begin
      # Extract original files from git history using safer approach
      repo_path = '/home/runner/work/ruby_routes/ruby_routes'
      commit_hash = '2ac1375'
      
      # Validate paths to prevent directory traversal
      radix_tree_path = File.join(repo_path, 'lib/ruby_routes/radix_tree.rb')
      node_path = File.join(repo_path, 'lib/ruby_routes/node.rb')
      
      unless File.exist?(File.dirname(radix_tree_path)) && File.exist?(File.dirname(node_path))
        puts "❌ Invalid file paths"
        return false
      end
      
      # Use IO.popen for safer command execution
      radix_content = IO.popen(['git', '-C', repo_path, 'show', "#{commit_hash}:lib/ruby_routes/radix_tree.rb"], &:read)
      node_content = IO.popen(['git', '-C', repo_path, 'show', "#{commit_hash}:lib/ruby_routes/node.rb"], &:read)
      
      if radix_content.empty? || node_content.empty?
        puts "❌ Failed to extract files from git history"
        return false
      end
      
      # Write to temporary files first
      File.write('/tmp/performance_comparison/radix_tree_main.rb', radix_content)
      File.write('/tmp/performance_comparison/node_main.rb', node_content)
      
      # Copy to target locations
      FileUtils.cp('/tmp/performance_comparison/radix_tree_main.rb', radix_tree_path)
      FileUtils.cp('/tmp/performance_comparison/node_main.rb', node_path)
      
      puts "✅ Main branch files restored"
      true
    rescue => e
      puts "❌ Failed to restore main branch files: #{e.message}"
      false
    end
  end

  def self.restore_optimized_files
    puts "🔄 Restoring optimized files..."
    
    FileUtils.cp('/tmp/performance_comparison/radix_tree_optimized.rb', 
                 '/home/runner/work/ruby_routes/ruby_routes/lib/ruby_routes/radix_tree.rb')
    FileUtils.cp('/tmp/performance_comparison/node_optimized.rb', 
                 '/home/runner/work/ruby_routes/ruby_routes/lib/ruby_routes/node.rb')
    puts "✅ Optimized files restored"
  end

  def self.run_performance_benchmark(version_name)
    puts "\n" + "🚀 " + "=" * 55
    puts "RUNNING PERFORMANCE TEST: #{version_name.upcase}"
    puts "=" * 60
    
    # Run the existing performance benchmark
    Dir.chdir('/home/runner/work/ruby_routes/ruby_routes') do
      puts "Executing: ruby benchmark/performance_optimized.rb"
      puts "-" * 60
      
      # Set PATH to include user gems safely
      original_path = ENV['PATH']
      gem_path = "/home/runner/.local/share/gem/ruby/3.2.0/bin"
      
      # Validate gem path exists before adding to PATH
      if File.directory?(gem_path)
        ENV['PATH'] = "#{gem_path}:#{original_path}"
      end
      
      begin
        # Use safer command execution
        start_time = Time.now
        result = system('ruby', 'benchmark/performance_optimized.rb')
        end_time = Time.now
        
        puts "-" * 60
        puts "Benchmark completed in #{(end_time - start_time).round(2)} seconds"
        puts "Exit status: #{result ? 'SUCCESS' : 'FAILED'}"
        
        result
      ensure
        # Restore original PATH
        ENV['PATH'] = original_path
      end
    end
  end

  def self.run_full_comparison
    puts "Starting performance comparison between main and optimized branches...\n"
    
    backup_current_files
    
    begin
      # Test main branch version
      if restore_main_branch_files
        puts "\n⏱️  About to run benchmark for MAIN BRANCH (original implementation)"
        puts "Press Enter to continue..."
        gets
        
        main_success = run_performance_benchmark("Main Branch (Original)")
        
        if main_success
          puts "\n✅ Main branch benchmark completed successfully"
        else
          puts "\n❌ Main branch benchmark failed"
        end
      else
        puts "\n❌ Could not restore main branch files, skipping main branch test"
        main_success = false
      end
      
      # Brief pause and prepare for optimized version
      puts "\n" + "⏱️ " * 20
      puts "Now preparing to test the OPTIMIZED VERSION..."
      puts "Press Enter to continue..."
      gets
      
      # Test optimized version
      restore_optimized_files
      optimized_success = run_performance_benchmark("Current Branch (Optimized)")
      
      if optimized_success
        puts "\n✅ Optimized branch benchmark completed successfully"
      else
        puts "\n❌ Optimized branch benchmark failed"
      end
      
      # Summary
      puts "\n" + "📊 " + "=" * 55
      puts "COMPARISON SUMMARY"
      puts "=" * 60
      
      if main_success && optimized_success
        puts "✅ Both benchmarks completed successfully!"
        puts
        puts "Key improvements expected in the optimized version:"
        puts "• 🎯 Longest prefix matching for better route resolution"
        puts "• ⚡ Improved LRU cache hit rates"
        puts "• 🧊 Frozen static keys for memory efficiency"
        puts "• 📈 Better overall performance characteristics"
        puts
        puts "Compare the benchmark results above to see the performance gains."
      elsif optimized_success
        puts "✅ Optimized benchmark completed (main branch test was skipped/failed)"
        puts "The optimized version shows the current performance characteristics."
      else
        puts "❌ One or both benchmarks failed. Check the output above for errors."
      end
      
    ensure
      # Always restore optimized files
      restore_optimized_files
      puts "\n🔄 Restored optimized files for continued development"
    end
  end
end

# Additional test for specific optimizations
def run_specific_optimization_tests
  puts "\n" + "🔬 " + "=" * 55
  puts "SPECIFIC OPTIMIZATION TESTS"
  puts "=" * 60
  
  # Set PATH for gems
  ENV['PATH'] = "/home/runner/.local/share/gem/ruby/3.2.0/bin:#{ENV['PATH']}"
  
  puts "Testing longest prefix matching behavior..."
  
  # Create a simple test to demonstrate the optimization
  test_script = <<~RUBY
    require_relative 'lib/ruby_routes'
    
    router = RubyRoutes.draw do
      get '/api', to: 'api#index'
      get '/api/users', to: 'users#index'
      get '/api/users/:id', to: 'users#show'
    end
    
    # Test longest prefix matching
    test_paths = [
      '/api/nonexistent',     # Should match /api with longest prefix
      '/api/users/123/posts', # Should match /api/users/:id with longest prefix
    ]
    
    puts "Testing longest prefix matching:"
    test_paths.each do |path|
      result = router.route_set.match('GET', path)
      puts "  #{path}: #{result ? 'MATCHED' : 'NO MATCH'}"
    end
    
    puts "\\nTesting cache performance with repeated access:"
    require 'benchmark'
    
    static_routes = (1..50).map { |i| "/static/route#{i}" }
    
    # Add many static routes
    static_routes.each_with_index do |route, i|
      router.get route, to: "static#{i}#index"
    end
    
    time = Benchmark.measure do
      5000.times do
        static_routes.each { |route| router.route_set.match('GET', route) }
      end
    end
    
    puts "Cache performance test: #{time.real.round(4)}s for 250,000 route matches"
    
    # Try to get cache stats
    begin
      if router.route_set.respond_to?(:cache_stats)
        stats = router.route_set.cache_stats
        puts "Cache hit rate: #{stats[:hit_rate]}"
        puts "Cache size: #{stats[:size]}"
      end
    rescue => e
      puts "Cache stats not available: #{e.message}"
    end
  RUBY
  
  File.write('/tmp/optimization_test.rb', test_script)
  
  Dir.chdir('/home/runner/work/ruby_routes/ruby_routes') do
    puts "Running optimization-specific tests..."
    system('ruby /tmp/optimization_test.rb')
  end
end

# Main execution
if __FILE__ == $0
  PerformanceComparison.run_full_comparison
  run_specific_optimization_tests
  
  puts "\n🎉 Performance comparison completed!"
  puts "Review the benchmark results above to see the impact of the optimizations."
end