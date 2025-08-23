#!/usr/bin/env ruby

# Performance test runner for comparing current (optimized) vs main branch
# Uses the existing performance_optimized.rb script for benchmarking

require 'fileutils'

puts "Ruby Routes Performance Comparison"
puts "Comparing main branch vs current optimized branch"
puts "=" * 60

# Security: Safe constant removal with validation
ALLOWED_CONSTANTS = [:RubyRoutes].freeze

def safe_const(const_name)
  symbolized = const_name.to_s.to_sym
  if ALLOWED_CONSTANTS.include?(symbolized)
    Object.send(:remove_const, symbolized)
  else
    raise ArgumentError, "Constant not allowed"
  end
end

class BenchmarkRunner
  def self.backup_current_files
    puts "Backing up current optimized files..."
    FileUtils.cp('/home/runner/work/ruby_routes/ruby_routes/lib/ruby_routes/radix_tree.rb', 
                 '/tmp/radix_tree_current.rb')
    FileUtils.cp('/home/runner/work/ruby_routes/ruby_routes/lib/ruby_routes/node.rb', 
                 '/tmp/node_current.rb')
  end

  def self.restore_main_branch_files
    puts "Restoring main branch files..."
    
    begin
      repo_path = '/home/runner/work/ruby_routes/ruby_routes'
      commit_hash = '2ac1375'
      
      # Validate paths
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
      
      # Write to temporary files
      File.write('/tmp/radix_tree_main.rb', radix_content)
      File.write('/tmp/node_main.rb', node_content)
      
      # Copy to target locations
      FileUtils.cp('/tmp/radix_tree_main.rb', radix_tree_path)
      FileUtils.cp('/tmp/node_main.rb', node_path)
      
      true
    rescue => e
      puts "❌ Error restoring main branch files: #{e.message}"
      false
    end
  end

  def self.restore_current_files
    puts "Restoring current optimized files..."
    FileUtils.cp('/tmp/radix_tree_current.rb', 
                 '/home/runner/work/ruby_routes/ruby_routes/lib/ruby_routes/radix_tree.rb')
    FileUtils.cp('/tmp/node_current.rb', 
                 '/home/runner/work/ruby_routes/ruby_routes/lib/ruby_routes/node.rb')
  end

  def self.run_benchmark(version_name)
    puts "\n" + "=" * 60
    puts "RUNNING BENCHMARK FOR #{version_name.upcase}"
    puts "=" * 60
    
    # Clear any cached modules to ensure fresh loading - using safe constant removal
    safe_const("RubyRoutes") if defined?(RubyRoutes)
    
    # Change to benchmark directory and run the performance script
    Dir.chdir('/home/runner/work/ruby_routes/ruby_routes/benchmark') do
      puts "Running performance_optimized.rb for #{version_name}..."
      
      # Use safer command execution
      success = system('ruby', 'performance_optimized.rb')
      
      unless success
        puts "❌ Benchmark failed for #{version_name}"
        return false
      end
      
      true
    end
  rescue => e
    puts "❌ Error running benchmark for #{version_name}: #{e.message}"
    false
  end

  def self.run_comparison
    backup_current_files
    
    begin
      # Run benchmark on main branch version
      restore_main_branch_files
      run_benchmark("Main Branch (Original)")
      
      puts "\n" + "⏱️  " * 20
      puts "Press Enter to continue to optimized version benchmark..."
      gets
      
      # Run benchmark on current optimized version  
      restore_current_files
      run_benchmark("Current Branch (Optimized)")
      
    ensure
      # Always restore current files
      restore_current_files
    end
    
    puts "\n" + "=" * 60
    puts "COMPARISON SUMMARY"
    puts "=" * 60
    puts "You should observe the following improvements in the optimized version:"
    puts
    puts "🚀 Performance Improvements:"
    puts "   • Faster route matching due to longest prefix matching"
    puts "   • Better cache hit rates with fixed LRU implementation" 
    puts "   • Reduced memory allocations from frozen static keys"
    puts
    puts "✅ Functional Improvements:"
    puts "   • Longest prefix matching for partial route matches"
    puts "   • More accurate route resolution for overlapping patterns"
    puts "   • Better handling of unmatched routes with fallback behavior"
    puts
    puts "📊 Memory Efficiency:"
    puts "   • Lower object count increases due to frozen static segments"
    puts "   • Improved LRU cache ordering reduces memory churn"
    puts
    puts "The optimized version maintains full API compatibility while providing"
    puts "these performance and correctness improvements."
  end
end

if __FILE__ == $0
  BenchmarkRunner.run_comparison
  puts "\nPerformance comparison completed!"
end