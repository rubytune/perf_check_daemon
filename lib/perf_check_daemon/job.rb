
require 'erb'
require 'shellwords'
require 'json'

require 'perf_check'

require "perf_check_daemon/configure"

module PerfCheckDaemon
  class Job
    @queue = :perf_check_jobs

    def self.perform(job)
      perf_check = PerfCheck.new(config.app.path)

      with_clean_env do
        perf_check.load_config
        prepare_app(job)

        defaults = config.defaults || ''
        job['arguments'] = "#{defaults} #{job.fetch('arguments').strip}".strip

        args = Shellwords.shellsplit(job['arguments'])
        perf_check.option_parser.parse(args).each do |route|
          perf_check.add_test_case(route.strip)
        end
        perf_check.run
      end

      post_results(job, perf_check)
    rescue OptionParser::InvalidOption => e
      post_error(job, e)
    rescue PerfCheck::Exception => e
      post_error(job, e)
    end

    def self.post_results(job, perf_check)
      gist_name = "#{job['branch']}-#{job['sha'][0,7]}" <<
                  "-#{job['reference']}-#{job['reference_sha'][0,7]}.md"
      gist_name.gsub!('/', '_')

      gist = { gist_name => { content: gist_content(job, perf_check) } }
      gist = api "/gists", { public: false, files: gist }, post: true

      comment = { body: comment_content(job, perf_check, gist.fetch('html_url')) }

      # Remove this when poller is deleted
      if job.key?('pull_request_comment_id')
        comment[:in_reply_to] = job['pull_request_comment_id']
      end

      api job.fetch('pull_request_comments'), comment, post: true

      true
    end

    def self.post_error(job, error)
      message = "There was an error running `perf_check #{job['arguments'].strip}`:"
      message << "\n\n    #{error.class}: "
      error.message.lines.each{ |line| message << line << "\n    " }
      api job.fetch('pull_request_comments'), { body: message.strip }, post: true
    end

    def self.gist_content(job, perf_check)
      b = GistHelper.new(job, perf_check).instance_eval{ binding }
      erb = ERB.new(File.read(gist_template), nil, '<>')
      erb.filename = gist_template
      erb.result(b)
    end

    def self.comment_content(job, perf_check, gist_url)
      b = CommentHelper.new(job, perf_check, gist_url).instance_eval{ binding }
      erb = ERB.new(File.read(comment_template), nil, '-')
      erb.filename = comment_template
      erb.result(b)
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
          ":white_check_mark: Reduced AR queries from #{test_case.reference_query_count} to #{test_case.this_query_count}!\n"
        elsif test_case.this_query_count > test_case.reference_query_count && test_case.this_query_count >= l
          ":x: Increased AR queries from #{test_case.reference_query_count} to #{test_case.this_query_count}!\n"
        elsif test_case.this_query_count == test_case.reference_query_count && test_case.reference_query_count >= l
          ":warning: #{test_case.this_query_count} AR queries were made\n"
        end
      end

      def absolute_latency_check(test_case)
        limit = config.limits.latency
        if test_case.this_latency > limit
          sprintf(":warning: Takes over %.1f seconds", limit.to_f / 1000)
        end
      end

      def backtrace_dump(test_case)
        this_trace = test_case.this_profiles.map(&:backtrace).compact.first
        reference_trace = test_case.reference_profiles.map(&:backtrace).compact.first

        message = ''
        if this_trace
          gist = backtrace_url(job['branch'], this_trace)
          message = ":mag: [Backtrace captured](#{gist}) (this branch)\n\n"
        end

        if reference_trace
          gist = backtrace_url(job['reference'], reference_trace)
          message << ":mag: [Backtrace captured](#{gist}) (#{job['reference']})"
        end

        message
      end

      def http_errors(test_case)
        statuses = test_case.this_profiles.map{ |p| p.response_code }
        statuses += test_case.reference_profiles.map{ |p| p.response_code }
        statuses.uniq.reject{ |code| (200...400).include?(code) }
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
    end
  end
end

