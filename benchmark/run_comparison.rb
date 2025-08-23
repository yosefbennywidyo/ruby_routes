#!/usr/bin/env ruby

# Compare MAIN commit vs current working tree in completely ISOLATED Ruby processes.
# No in‑process constant unloading (safer & truer measurements).

require 'fileutils'
require 'open3'
require 'json'
require 'rbconfig'

puts "Ruby Routes Performance Comparison (Isolated Processes)"
puts "=" * 60

ROOT        = File.expand_path('../..', __dir__)
LIB_PATH    = File.join(ROOT, 'lib', 'ruby_routes')
RADIX_FILE  = File.join(LIB_PATH, 'radix_tree.rb')
NODE_FILE   = File.join(LIB_PATH, 'node.rb')
MAIN_COMMIT = '2ac1375'
BENCH_FILE  = File.join(ROOT, 'benchmark', 'performance_optimized.rb')

class BenchmarkRunner
  class << self
    def backup_current_files
      @radix_backup = File.read(RADIX_FILE)
      @node_backup  = File.read(NODE_FILE)
    end

    def restore_current_files
      File.write(RADIX_FILE, @radix_backup) if @radix_backup
      File.write(NODE_FILE,  @node_backup)  if @node_backup
    end

    def checkout_main_files
      radix_src = git_show("lib/ruby_routes/radix_tree.rb")
      node_src  = git_show("lib/ruby_routes/node.rb")
      File.write(RADIX_FILE, radix_src)
      File.write(NODE_FILE,  node_src)
    end

    def git_show(path)
      cmd = ['git','-C', ROOT, 'show', "#{MAIN_COMMIT}:#{path}"]
      out, err, status = Open3.capture3(*cmd)
      raise "git show failed: #{err}" unless status.success? && !out.empty?
      out
    end

    # Run benchmark script in a fresh Ruby VM
    # Returns raw stdout and parsed JSON (if possible)
    def run_subprocess(label)
      raise "Benchmark script missing: #{BENCH_FILE}" unless File.exist?(BENCH_FILE)
      env = { 'RR_VERSION' => label }
      stdout, stderr, status = Open3.capture3(env, RbConfig.ruby, BENCH_FILE)
      unless status.success?
        warn "[#{label}] benchmark failed (exit #{status.exitstatus})"
        warn stderr unless stderr.empty?
      end
      parsed = begin
        JSON.parse(stdout, symbolize_names: true)
      rescue JSON::ParserError
        {}
      end
      [stdout, parsed]
    end

    def compare(main_json, current_json)
      keys = (main_json.keys + current_json.keys).uniq
      puts "\nCOMPARISON (MAIN vs CURRENT)"
      keys.each do |k|
        mv = main_json[k]
        cv = current_json[k]
        if mv.is_a?(Numeric) && cv.is_a?(Numeric) && mv > 0
          delta = ((cv - mv) / mv * 100.0)
          arrow = delta < 0 ? '↓' : '↑'
          printf "%-28s main=%-9.4f curr=%-9.4f (%s%.2f%%)\n", k, mv, cv, arrow, delta.abs
        else
          printf "%-28s main=%-12s curr=%-12s\n", k, mv.inspect, cv.inspect
        end
      end
    end

    def run
      backup_current_files

      puts "\n== Running MAIN commit (#{MAIN_COMMIT}) in isolated process =="
      checkout_main_files
      main_stdout, main_json = run_subprocess('MAIN')

      puts "\n== Running CURRENT working tree in isolated process =="
      restore_current_files
      curr_stdout, curr_json = run_subprocess('CURRENT')

      # Auto-detect if JSON missing (fallback: show raw first lines)
      if main_json.empty? || curr_json.empty?
        puts "\nWARNING: Benchmark output not JSON; showing first lines."
        puts "\n--- MAIN STDOUT (truncated) ---"
        puts main_stdout.lines.first(20).join
        puts "\n--- CURRENT STDOUT (truncated) ---"
        puts curr_stdout.lines.first(20).join
      else
        compare(main_json, curr_json)
      end
    ensure
      restore_current_files
    end
  end
end

if __FILE__ == $0
  BenchmarkRunner.run
end
