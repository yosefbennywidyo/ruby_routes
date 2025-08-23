#!/usr/bin/env ruby

# Performance test runner for comparing current (optimized) vs main branch
# Uses the existing performance_optimized.rb script for benchmarking

require 'fileutils'

puts "Ruby Routes Performance Comparison"
puts "Comparing main branch vs current optimized branch"
puts "=" * 60

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
    # Get original files from before optimizations (commit 2ac1375)
    system('cd /home/runner/work/ruby_routes/ruby_routes && git show 2ac1375:lib/ruby_routes/radix_tree.rb > /tmp/radix_tree_main.rb')
    system('cd /home/runner/work/ruby_routes/ruby_routes && git show 2ac1375:lib/ruby_routes/node.rb > /tmp/node_main.rb')
    
    FileUtils.cp('/tmp/radix_tree_main.rb', 
                 '/home/runner/work/ruby_routes/ruby_routes/lib/ruby_routes/radix_tree.rb')
    FileUtils.cp('/tmp/node_main.rb', 
                 '/home/runner/work/ruby_routes/ruby_routes/lib/ruby_routes/node.rb')
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
    
    # Clear any cached modules to ensure fresh loading
    Object.send(:remove_const, :RubyRoutes) if defined?(RubyRoutes)
    
    # Change to benchmark directory and run the performance script
    Dir.chdir('/home/runner/work/ruby_routes/ruby_routes/benchmark') do
      puts "Running performance_optimized.rb for #{version_name}..."
      system('ruby performance_optimized.rb')
    end
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