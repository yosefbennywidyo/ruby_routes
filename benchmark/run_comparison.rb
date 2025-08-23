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
MAIN_COMMIT = '2ac1375'.freeze
BENCH_FILE  = File.join(ROOT, 'benchmark', 'performance_optimized.rb')

class BenchmarkRunner
  class << self
    # Whitelist the only files we ever checkout (prevents arbitrary path injection)
    ALLOWED_FILES = %w[
      lib/ruby_routes/radix_tree.rb
      lib/ruby_routes/node.rb
    ].freeze
    COMMIT_SHA_REGEX = /\A[0-9a-f]{5,40}\z/.freeze

    def backup_current_files
      @radix_backup = File.read(RADIX_FILE)
      @node_backup  = File.read(NODE_FILE)
    end

    def restore_current_files
      File.write(RADIX_FILE, @radix_backup) if @radix_backup
      File.write(NODE_FILE,  @node_backup)  if @node_backup
    end

    def checkout_main_files
      radix_src = git_show('lib/ruby_routes/radix_tree.rb')
      node_src  = git_show('lib/ruby_routes/node.rb')
      File.write(RADIX_FILE, radix_src)
      File.write(NODE_FILE,  node_src)
    end

    def git_show(path)
      unless ALLOWED_FILES.include?(path)
        raise ArgumentError, "Refusing to git show unapproved path: #{path}"
      end
      unless MAIN_COMMIT.match?(COMMIT_SHA_REGEX)
        raise ArgumentError, "Invalid MAIN_COMMIT format"
      end
      cmd = ['git', '-C', ROOT, 'show', "#{MAIN_COMMIT}:#{path}"]
      # Array form (no shell); no user input in command position -> safe
      out, err, status = Open3.capture3(*cmd)
      raise "git show failed: #{err}" unless status.success? && !out.empty?
      out
    end

    # Secure alternative to Open3.capture3 using Process.spawn + pipes (no shell),
    # single combined stdout+stderr stream; avoids command injection by:
    #  - Validating BENCH_FILE path
    #  - Using array args (no interpolation)
    #  - Restricting ENV keys we pass through
    SAFE_ENV_KEYS = %w[RR_VERSION].freeze

    def run_subprocess(label)
      raise "Benchmark script missing: #{BENCH_FILE}" unless File.file?(BENCH_FILE)
      bench_path = File.realpath(BENCH_FILE)
      root_path  = File.realpath(ROOT)
      unless bench_path.start_with?(root_path + File::SEPARATOR)
        raise "Refusing to execute script outside repo root"
      end

      # Minimal environment (inherit nothing except needed var)
      env = { 'RR_VERSION' => label.to_s }

      r_out, w_out = IO.pipe
      pid = Process.spawn(env, RbConfig.ruby, '--disable-gems', bench_path,
                          out: w_out, err: :out)
      w_out.close
      stdout = r_out.read
      r_out.close
      Process.wait(pid)
      status = $?

      unless status.success?
        warn "[#{label}] benchmark failed (exit #{status.exitstatus})"
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
