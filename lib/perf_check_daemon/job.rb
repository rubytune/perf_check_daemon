
require 'erb'
require 'shellwords'
require 'json'

require 'perf_check'

require "perf_check_daemon/configure"
require "perf_check_daemon/finished_job"

module PerfCheckDaemon
  class Job
    @queue = :perf_check_jobs

    class << self
      attr_reader :queue
    end

    def self.id(timestamp)
      timestamp = DateTime.parse(timestamp) if timestamp.is_a?(String)
      timestamp.to_time.strftime("%Y%m%d%H%M%S.%L")
    end

    def self.log_path(timestamp)
      log = "log/perf_checks/#{id(timestamp)}.txt"
      log = File.expand_path("#{File.dirname(__FILE__)}/../../#{log}")
      system("mkdir", "-p", File.dirname(log))
      log
    end

    def self.perform(job)
      stdout = $stdout.dup
      stderr = $stderr.dup
      log = File.open(log_path(job["created_at"]), "w+")
      $stdout.reopen(log)
      $stderr.reopen(log)

      perf_check = nil

      with_clean_env do
        prepare_app(job)

        perf_check = PerfCheck.new(config.app.path)
        perf_check.load_config

        defaults = config.defaults || ''
        job['arguments'] = "#{defaults} #{job.fetch('arguments').strip}".strip

        perf_check.parse_arguments(job['arguments'])
        perf_check.run
      end
      
      details = post_results(job, perf_check)
      create_finished_job(job, details)
    rescue OptionParser::InvalidOption => e
      details = post_error(job, e)
      create_finished_job(job, details, failed: true)
    rescue PerfCheck::Exception => e
      details = post_error(job, e)
      create_finished_job(job, details, failed: true)
    ensure
      $stdout.reopen(stdout)
      $stderr.reopen(stderr)
    end

    def self.post_results(job, perf_check)
      gist_name = "#{job['branch']}-#{job['sha'][0,7]}" <<
                  "-#{job['reference']}-#{job['reference_sha'][0,7]}.md"
      gist_name.gsub!('/', '_')

      gist = { gist_name => { content: gist_content(job, perf_check) } }
      gist = api "/gists", { public: false, files: gist }, post: true

      comment = { body: comment_content(job, perf_check, gist.fetch('html_url')) }

      api job.fetch('issue_comments'), comment, post: true
      comment[:body]
    end

    def self.create_finished_job(job, details, failed: false)
      FinishedJob.create(
        issue_title: job["issue_title"],
        issue_url: job["issue_html_url"],
        github_user: job["github_holder"]["user"]["login"],
        branch: job["branch"],
        arguments: job["arguments"],
        job_enqueued_at: job["created_at"],
        job_id: id(job["created_at"]),
        failed: failed,
        details: details
      )
    end

    def self.post_error(job, error)
      message = "Problem running `perf_check #{job['arguments'].strip}`:"
      message << "\n\n    #{error.class}: "
      error.message.lines.each{ |line| message << line << "\n    " }
      api job.fetch('issue_comments'), { body: message.strip }, post: true
      message
    end

    def self.gist_content(job, perf_check)
      b = GistHelper.new(job, perf_check).instance_eval{ binding }
      erb = ERB.new(File.read(gist_template), nil, '<>')
      erb.filename = gist_template
      erb.result(b)
    end

    def self.comment_content(job, perf_check, gist_url)
      h = CommentHelper.new(job, perf_check, gist_url)
      h.comment
    end

    def self.with_clean_env
      git_ssh = ENV['GIT_SSH']
      Bundler.with_clean_env do
        ENV['GIT_SSH'] = git_ssh
        yield
      end
    end

    def self.prepare_app(job)
      app_path = Shellwords.escape(config.app.path)
      branch = Shellwords.escape(job.fetch('branch'))
      capture("cd #{app_path} &&
               git remote prune origin 1>&2 &&
               git fetch --all 1>&2 &&
               git checkout master 1>&2 &&
               git submodule update 1>&2 &&
               git pull 1>&2 &&
               git checkout #{branch} 1>&2 &&
               git submodule update 1>&2 &&
               git pull 1>&2 &&
               git submodule update 1>&2 &&
               bundle 1>&2")
    end

    def self.capture(command)
      warn(command)
      `#{command}`
    end

    class GistHelper
      attr_reader :job, :perf_check, :gist_url

      def initialize(job, perf_check)
        @job, @perf_check = job, perf_check
      end
    end

    class CommentHelper
      attr_reader :job, :perf_check, :gist_url

      def initialize(job, perf_check, gist_url)
        @job, @perf_check, @gist_url = job, perf_check, gist_url
      end

      def comment
        perf_check.options.diff ? diff_comment : regular_comment
      end

      def regular_comment
        results = perf_check.test_cases.map do |test_case|
          if http_errors(test_case).empty?
            ["**#{ test_case.resource }**",
             "#{latency_check(test_case)} #{latency_change(test_case)}",
             query_check_and_change(test_case),
             absolute_latency_check(test_case),
             response_diff_check(test_case)].grep(/\S/).join("\n")
          else
            ["**#{ test_case.resource }**",
             ":x: Encountered HTTP errors (#{ http_errors(test_case).join(', ') })",
             backtrace_dump(test_case)].grep(/\S/).join("\n")
          end
        end

        results.join("\n\n") << "\n\n[See more details](#{ gist_url })."
      end

      def diff_comment
        results = perf_check.test_cases.map do |test_case|
          if http_errors(test_case).empty?
            ["**#{ test_case.resource }**",
             response_diff_check(test_case),
             redirect_check(test_case)].grep(/\S/).join("\n")
          else
            ["**#{ test_case.resource }**",
             ":x: Encountered HTTP errors (#{ http_errors(test_case).join(', ') })",
             backtrace_dump(test_case)].grep(/\S/).join("\n")
          end
        end

        results.join("\n\n")
      end

      def latency_check(test_case)
        threshold = config.limits.change_factor
        test_case.speedup_factor >= (1 - threshold) ? ':white_check_mark:' : ':x:'
      end

      def latency_change(test_case)
        ref = perf_check.options.reference
        threshold = config.limits.change_factor
        if test_case.speedup_factor < 1 - threshold
          sprintf('%.1fx slower than %s', 1/test_case.speedup_factor, ref)
        elsif test_case.speedup_factor > 1 + threshold
          sprintf('%.1fx faster than %s', test_case.speedup_factor.abs, ref)
        else
          "about the same as #{ref}"
        end + sprintf(' (%dms vs %dms)', test_case.this_latency, test_case.reference_latency)
      end

      def query_check_and_change(test_case)
        l = config.limits.queries
        if test_case.this_query_count < test_case.reference_query_count && test_case.reference_query_count >= l
          ":white_check_mark: Reduced AR queries from #{test_case.reference_query_count} to #{test_case.this_query_count}!"
        elsif test_case.this_query_count > test_case.reference_query_count && test_case.this_query_count >= l
          ":x: Increased AR queries from #{test_case.reference_query_count} to #{test_case.this_query_count}!"
        elsif test_case.this_query_count == test_case.reference_query_count && test_case.reference_query_count >= l
          ":warning: #{test_case.this_query_count} AR queries were made"
        end
      end

      def absolute_latency_check(test_case)
        limit = config.limits.latency
        if test_case.this_latency > limit
          sprintf(":warning: Takes over %.1f seconds", limit.to_f / 1000)
        end
      end

      def response_diff_check(test_case)
        if perf_check.options.verify_no_diff
          diff = test_case.response_diff
          if diff.changed?
            changes = File.read(diff.file)
            gist = diff_url(job["branch"], changes)
            message = ":mag: [Diff captured](#{gist})"
            message << "\n```diff\n#{changes.chomp}\n```" if changes.lines.length <= 9
            message
          else
            ":white_check_mark: Response was identical to #{perf_check.options.reference}"
          end
        end
      ensure
        File.delete(diff.file) if diff && diff.changed?
      end

      def backtrace_dump(test_case)
        this_trace = test_case.this_profiles.map(&:backtrace).compact.first
        reference_trace = test_case.reference_profiles.map(&:backtrace).compact.first

        messages = []
        if this_trace
          gist = backtrace_url(job['branch'], this_trace)
          messages << ":mag: [Backtrace captured](#{gist}) (this branch)"
        end

        if reference_trace
          gist = backtrace_url(job['reference'], reference_trace)
          messages << ":mag: [Backtrace captured](#{gist}) (#{job['reference']})"
        end

        messages.join("\n")
      end

      def http_errors(test_case)
        statuses = test_case.this_profiles.map{ |p| p.response_code }
        statuses += test_case.reference_profiles.map{ |p| p.response_code }
        statuses.uniq.reject{ |code| (200...400).include?(code) }
      end

      def redirect_check(test_case)
        messages = []

        if (code = test_case.this_profiles.map(&:response_code).find{|x| (300...400).include?(x)})
          messages << ":grey_exclamation: This branch responded with a #{code} redirect"
        end

        if (code = test_case.reference_profiles.map(&:response_code).find{|x| (300...400).include?(x)})
          messages << ":grey_exclamation: #{perf_check.options.reference} responded with a #{code} redirect"
        end

        messages.join("\n")
      end

      private

      def backtrace_url(branch, trace)
        gist_name = "#{branch}-backtrace.md"
        gist_name.gsub!('/', '_')

        content = "### #{trace[0]}\n\n"
        content << "file | method\n"
        content << "-----|-------\n"
        trace[1..-1].grep(/^#{config.app.path}\//).each do |line|
          line = line.sub(/^#{config.app.path}\/(.+):(\d+):in/) do |l|
            file = l.match(/^#{config.app.path}\/(.+):\d+:in/)[1]
            line = l.match(/^#{config.app.path}\/.+:(\d+):in/)[1]
            url = "https://www.github.com/#{config.github.repo}/"
            url << "blob/#{branch}/#{file}#L#{line}"
            "[#{file}:#{line}](#{url}):in"
          end

          file, method = line.split(/:in /, 2)
          content << "#{file} | #{method}\n"
        end

        gist = { gist_name => { content: content } }
        gist = api "/gists", { public: false, files: gist }, post: true

        gist.fetch('html_url')
      end

      def diff_url(branch, diff)
        gist_name = "#{branch}-#{Time.now.to_i}.diff"
        gist_name.gsub!('/', '_')

        gist = { gist_name => { content: diff } }
        gist = api "/gists", { public: false, files: gist }, post: true

        gist.fetch("html_url")
      end
    end
  end
end

