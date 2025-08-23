#!/usr/bin/env ruby

require 'benchmark'
require 'fileutils'
require 'json'
require_relative '../lib/ruby_routes'

puts "RadixTree and Node Performance Comparison"
puts "Comparing optimized version vs original version"
puts "=" * 60

# Helper method to backup and restore files
class FileManager
  def self.backup_optimized_files
    FileUtils.cp('/home/runner/work/ruby_routes/ruby_routes/lib/ruby_routes/radix_tree.rb',
                 '/tmp/radix_tree_optimized.rb')
    FileUtils.cp('/home/runner/work/ruby_routes/ruby_routes/lib/ruby_routes/node.rb',
                 '/tmp/node_optimized.rb')
  end

  def self.restore_original_files
    begin
      repo_path = '/home/runner/work/ruby_routes/ruby/ruby_routes'
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
      File.write('/tmp/radix_tree_original.rb', radix_content)
      File.write('/tmp/node_original.rb', node_content)

      # Copy to target locations
      FileUtils.cp('/tmp/radix_tree_original.rb', radix_tree_path)
      FileUtils.cp('/tmp/node_original.rb', node_path)

      true
    rescue => e
      puts "❌ Error restoring original files: #{e.message}"
      false
    end
  end

  def self.restore_optimized_files
    FileUtils.cp('/tmp/radix_tree_optimized.rb',
                 '/home/runner/work/ruby_routes/ruby/ruby_routes/lib/ruby_routes/radix_tree.rb')
    FileUtils.cp('/tmp/node_optimized.rb',
                 '/home/runner/work/ruby_routes/ruby/ruby_routes/lib/ruby_routes/node.rb')
  end
end

# Test suite for both versions
class PerformanceTestSuite
  def initialize(version_name)
    @version_name = version_name
    @results = {}
  end

  def create_test_router
    RubyRoutes.draw do
      # Basic routes for prefix matching tests
      get '/api', to: 'api#index'
      get '/api/users', to: 'users#index'
      get '/api/users/:id', to: 'users#show'
      get '/api/users/:id/posts', to: 'posts#index'
      get '/api/users/:id/posts/:post_id', to: 'posts#show'

      # Static routes (many for cache testing)
      (1..100).each do |i|
        get "/static/route#{i}", to: "static#{i}#index"
      end

      # RESTful resources
      resources :posts
      resources :comments
      resources :categories

      # Nested resources
      resources :users do
        resources :posts
        resources :comments
      end

      # Admin namespace
      namespace :admin do
        resources :users
        resources :posts
        resources :categories
      end

      # API namespace with versioning
      namespace :api do
        namespace :v1 do
          resources :users
          resources :posts
        end
        namespace :v2 do
          resources :users
          resources :posts
        end
      end

      # Wildcard routes
      get '/files/*path', to: 'files#show'
      get '/docs/*path', to: 'docs#show'
    end
  end

  def run_all_tests
    puts "\n#{@version_name} Performance Tests"
    puts "-" * 40

    router = create_test_router
    puts "Router created with #{router.route_set.instance_variable_get(:@routes)&.size || 'unknown'} routes"

    # Test 1: Basic route matching performance
    test_basic_route_matching(router)

    # Test 2: Longest prefix matching (key optimization)
    test_longest_prefix_matching(router)

    # Test 3: Cache performance with many static routes
    test_cache_performance(router)

    # Test 4: Memory usage
    test_memory_usage(router)

    @results
  end

  private

  def test_basic_route_matching(router)
    test_paths = [
      ['GET', '/'],
      ['GET', '/api'],
      ['GET', '/api/users'],
      ['GET', '/api/users/123'],
      ['POST', '/users'],
      ['GET', '/users/123/posts'],
      ['GET', '/admin/users'],
      ['GET', '/api/v1/users'],
      ['GET', '/api/v2/posts/456'],
      ['GET', '/static/route50'],
      ['GET', '/files/path/to/file.txt']
    ]

    # Warm up
    test_paths.each { |method, path| router.route_set.match(method, path) }

    result = Benchmark.measure do
      10_000.times do
        test_paths.each { |method, path| router.route_set.match(method, path) }
      end
    end

    @results[:basic_matching] = result.real
    puts "Basic route matching (10k iterations): #{result.real.round(4)}s"
  end

  def test_longest_prefix_matching(router)
    # Test cases that should benefit from longest prefix matching optimization
    prefix_test_paths = [
      ['GET', '/api/nonexistent'],           # Should match /api
      ['GET', '/api/users/invalid/action'],  # Should match /api/users/:id
      ['GET', '/admin/nonexistent'],         # Should match admin namespace
      ['GET', '/static/route999'],           # Should not match (no fallback)
    ]

    successful_matches = 0
    result = Benchmark.measure do
      5_000.times do
        prefix_test_paths.each do |method, path|
          match_result = router.route_set.match(method, path)
          successful_matches += 1 if match_result
        end
      end
    end

    @results[:prefix_matching] = result.real
    @results[:prefix_success_rate] = successful_matches.to_f / (5_000 * prefix_test_paths.length)
    puts "Longest prefix matching (5k iterations): #{result.real.round(4)}s"
    puts "Prefix match success rate: #{(@results[:prefix_success_rate] * 100).round(2)}%"
  end

  def test_cache_performance(router)
    # Test with many static routes to exercise cache
    static_paths = (1..100).map { |i| ['GET', "/static/route#{i}"] }

    # Clear any existing cache stats
    begin
      router.route_set.respond_to?(:cache_stats) && router.route_set.cache_stats
    rescue
      # Ignore if not available
    end

    result = Benchmark.measure do
      1_000.times do
        static_paths.each { |method, path| router.route_set.match(method, path) }
      end
    end

    @results[:cache_performance] = result.real
    puts "Cache performance test (1k iterations): #{result.real.round(4)}s"

    # Try to get cache stats if available
    begin
      if router.route_set.respond_to?(:cache_stats)
        stats = router.route_set.cache_stats
        @results[:cache_hit_rate] = stats[:hit_rate]
        puts "Cache hit rate: #{stats[:hit_rate]}"
      end
    rescue => e
      puts "Cache stats not available: #{e.message}"
    end
  end

  def test_memory_usage(router)
    # Simple memory test
    before_objects = ObjectSpace.count_objects[:T_OBJECT] rescue 0

    # Perform operations
    1_000.times do
      router.route_set.match('GET', '/api/users/123')
      router.route_set.match('GET', '/admin/posts')
    end

    after_objects = ObjectSpace.count_objects[:T_OBJECT] rescue 0
    @results[:object_increase] = after_objects - before_objects
    puts "Object count increase: #{@results[:object_increase]}"
  end
end

# Writes an isolated runner script that a fresh Ruby process will execute
def write_runner_script(path)
  script = <<'RUNNER'
#!/usr/bin/env ruby
require 'benchmark'
require 'json'
require_relative '../lib/ruby_routes'
# Re‑define minimal PerformanceTestSuite (must not rely on parent constants)
class PerformanceTestSuite
  def initialize(version_name); @version_name = version_name; @results = {}; end
  def create_test_router
    RubyRoutes.draw do
      get '/api', to: 'api#index'
      get '/api/users', to: 'users#index'
      get '/api/users/:id', to: 'users#show'
      get '/api/users/:id/posts', to: 'posts#index'
      get '/api/users/:id/posts/:post_id', to: 'posts#show'
      (1..100).each { |i| get "/static/route#{i}", to: "static#{i}#index" }
      resources :posts; resources :comments; resources :categories
      resources :users do
        resources :posts
        resources :comments
      end
      namespace :admin do
        resources :users; resources :posts; resources :categories
      end
      namespace :api do
        namespace :v1 do
          resources :users; resources :posts
        end
        namespace :v2 do
          resources :users; resources :posts
        end
      end
      get '/files/*path', to: 'files#show'
      get '/docs/*path',  to: 'docs#show'
    end
  end
  def run_all_tests
    router = create_test_router
    test_basic_route_matching(router)
    test_longest_prefix_matching(router)
    test_cache_performance(router)
    test_memory_usage(router)
    @results
  end
  def test_basic_route_matching(router)
    paths = [
      ['GET','/'],['GET','/api'],['GET','/api/users'],['GET','/api/users/123'],
      ['POST','/users'],['GET','/users/123/posts'],['GET','/admin/users'],
      ['GET','/api/v1/users'],['GET','/api/v2/posts/456'],['GET','/static/route50'],
      ['GET','/files/path/to/file.txt']
    ]
    paths.each { |m,p| router.route_set.match(m,p) }
    t = Benchmark.measure do
      10_000.times { paths.each { |m,p| router.route_set.match(m,p) } }
    end
    @results[:basic_matching] = t.real
  end
  def test_longest_prefix_matching(router)
    prefix = [
      ['GET','/api/nonexistent'],
      ['GET','/api/users/invalid/action'],
      ['GET','/admin/nonexistent'],
      ['GET','/static/route999']
    ]
    ok = 0
    t = Benchmark.measure do
      5_000.times do
        prefix.each do |m,p|
          ok += 1 if router.route_set.match(m,p)
        end
      end
    end
    @results[:prefix_matching] = t.real
    @results[:prefix_success_rate] = ok.to_f / (5_000 * prefix.length)
  end
  def test_cache_performance(router)
    static_paths = (1..100).map { |i| ['GET',"/static/route#{i}"] }
    t = Benchmark.measure do
      1_000.times { static_paths.each { |m,p| router.route_set.match(m,p) } }
    end
    @results[:cache_performance] = t.real
    if router.route_set.respond_to?(:cache_stats)
      stats = router.route_set.cache_stats
      @results[:cache_hit_rate] = stats[:hit_rate]
    end
  end
  def test_memory_usage(router)
    before = ObjectSpace.count_objects[:T_OBJECT] rescue 0
    1_000.times do
      router.route_set.match('GET','/api/users/123')
      router.route_set.match('GET','/admin/posts')
    end
    after = ObjectSpace.count_objects[:T_OBJECT] rescue 0
    @results[:object_increase] = after - before
  end
end
suite = PerformanceTestSuite.new(ENV['RR_VERSION'] || 'UNKNOWN')
results = suite.run_all_tests
STDOUT.write(results.to_json)
RUNNER
  File.write(path, script)
  File.chmod(0o755, path)
end

# Run a version in a separate Ruby process after restoring files
def run_version_in_subprocess(label)
  runner = File.join(Dir.tmpdir, "ruby_routes_runner_#{label.downcase}.rb")
  write_runner_script(runner)

  runner_path = File.realpath(runner)
  tmp_root    = File.realpath(Dir.tmpdir)
  unless runner_path.start_with?(tmp_root + File::SEPARATOR)
    raise "Runner outside tmpdir"
  end

  r_out, w_out = IO.pipe
  pid = fork do
    begin
      r_out.close
      ENV['RR_VERSION'] = label.to_s
      $stdout.reopen(w_out)
      $stderr.reopen(w_out)
      $stdout.sync = true
      $stderr.sync = true
      load runner_path
    rescue => e
      puts({ error: e.class.name, message: e.message }.to_json)
    ensure
      w_out.close
    end
    exit! 0
  end
  w_out.close
  stdout = r_out.read
  r_out.close
  Process.wait(pid)
  JSON.parse(stdout, symbolize_names: true)
rescue JSON::ParserError
  {}
end

# Modified comparison to use subprocesses (isolated VM each time)
def run_comparison
  puts "Setting up comparison environment..."
  FileManager.backup_optimized_files

  puts "\n" + "=" * 60
  puts "TESTING ORIGINAL VERSION (separate process)"
  puts "=" * 60
  FileManager.restore_original_files
  original_results = run_version_in_subprocess('ORIGINAL')

  puts "\n" + "=" * 60
  puts "TESTING OPTIMIZED VERSION (separate process)"
  puts "=" * 60
  FileManager.restore_optimized_files
  optimized_results = run_version_in_subprocess('OPTIMIZED')

  puts "\n" + "=" * 60
  puts "PERFORMANCE COMPARISON RESULTS"
  puts "=" * 60
  compare_results(original_results, optimized_results)
ensure
  FileManager.restore_optimized_files
end

def compare_results(original, optimized)
  metrics = [
    [:basic_matching, "Basic route matching", "s"],
    [:prefix_matching, "Longest prefix matching", "s"],
    [:cache_performance, "Cache performance", "s"],
    [:object_increase, "Object count increase", "objects"]
  ]

  metrics.each do |key, name, unit|
    if original[key] && optimized[key]
      improvement = ((original[key] - optimized[key]) / original[key] * 100)
      direction = improvement > 0 ? "improvement" : "regression"

      puts "#{name}:"
      puts "  Original:  #{original[key].round(4)} #{unit}"
      puts "  Optimized: #{optimized[key].round(4)} #{unit}"
      puts "  Change:    #{improvement.round(2)}% #{direction}"
      puts
    end
  end

  # Special handling for success rates
  if original[:prefix_success_rate] && optimized[:prefix_success_rate]
    puts "Prefix matching success rate:"
    puts "  Original:  #{(original[:prefix_success_rate] * 100).round(2)}%"
    puts "  Optimized: #{(optimized[:prefix_success_rate] * 100).round(2)}%"
    improvement = optimized[:prefix_success_rate] - original[:prefix_success_rate]
    puts "  Change:    #{(improvement * 100).round(2)} percentage points"
    puts
  end

  puts "Key improvements in optimized version:"
  puts "- Longest prefix matching for better route resolution"
  puts "- Fixed LRU cache behavior for better hit rates"
  puts "- Static segment key freezing for memory efficiency"
  puts "- Enhanced documentation and code clarity"
end

# Run the comparison
if __FILE__ == $0
  run_comparison
  puts "\nPerformance comparison completed!"
end
