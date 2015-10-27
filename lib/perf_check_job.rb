

require 'erb'
require 'shellwords'

require_relative "configure"

class PerfCheckJob
  @queue = :perf_check_jobs

  def self.perform(job)
    args = job.fetch('arguments').strip
    defaults = config.defaults || ''

    app_path = Shellwords.escape(config.app.path)
    args = Shellwords.split(args).map{ |p| Shellwords.escape(p) }.join(' ')
    defaults = Shellwords.split(defaults).map{ |p| Shellwords.escape(p) }.join(' ')
    branch = Shellwords.escape(job.fetch('branch'))

    git_ssh = ENV['GIT_SSH']
    perf_check_output = Bundler.with_clean_env do
      ENV['GIT_SSH'] = git_ssh
      JSON.parse(`cd #{app_path} &&
                  git fetch --all 1>&2 &&
                  git checkout #{branch} 1>&2 &&
                  git submodule update 1>&2 &&
                  git pull 1>&2 &&
                  git submodule update 1>&2 &&
                  bundle 1>&2 &&
                  bundle exec perf_check #{defaults} -j #{args}`)
    end

    job = {
      branch: job.fetch('branch'),
      reference: job.fetch('reference'),
      branch_sha: job.fetch('sha'),
      reference_sha: job.fetch('reference_sha'),
      pull_request: job.fetch('pull_request'),
      pull_request_comments: job.fetch('pull_request_comments')
    }

    post_results(job, perf_check_output)
  end

  def self.post_results(job, perf_check_output)
    job[:checks] = perf_check_output.map do |check|
      {
        route: check.fetch('route'),
        latency: check.fetch('latency'),
        reference_latency: check.fetch('reference_latency'),
        latency_difference: check.fetch('latency_difference'),
        speedup_factor: check.fetch('speedup_factor'),
        query_count: check.fetch('query_count'),
        reference_query_count: check.fetch('reference_query_count')
      }.merge(
        requests: check.fetch('requests').map do |r|
          {
            latency: r.fetch('latency'),
            response_code: r.fetch('response_code'),
            query_count: r.fetch('query_count'),
            server_memory: r.fetch('server_memory')
          }
        end,
        reference_requests: check.fetch('reference_requests').map do |r|
          {
            latency: r.fetch('latency'),
            response_code: r.fetch('response_code'),
            query_count: r.fetch('query_count'),
            server_memory: r.fetch('server_memory')
          }
        end
      )
    end

    gist_name = "#{job[:branch]}-#{job[:branch_sha][0,7]}" <<
                "-#{job[:reference]}-#{job[:reference_sha][0,7]}.md"
    gist_name.gsub!('/', '_')

    gist = { gist_name => { content: gist_content(job) } }
    gist = api "/gists", { public: false, files: gist }, post: true

    comment = { body: comment_content(job, gist.fetch('html_url')) }
    api job.fetch(:pull_request_comments), comment, post: true

    true
  end

  def self.gist_content(job)
    b = GistHelper.new(job).instance_eval{ binding }
    erb = ERB.new(File.read(gist_template), nil, '<>')
    erb.filename = gist_template
    erb.result(b)
  end

  def self.comment_content(job, gist_url)
    b = CommentHelper.new(job, gist_url).instance_eval{ binding }
    erb = ERB.new(File.read(comment_template), nil, '<>')
    erb.filename = comment_template
    erb.result(b)
  end

  class GistHelper
    attr_reader :job, :gist_url

    def initialize(job)
      @job = job
    end
  end

  class CommentHelper
    attr_reader :job, :gist_url

    def initialize(job, gist_url)
      @job, @gist_url = job, gist_url
    end

    def latency_check(check)
      check[:speedup_factor] >= 0.8 ? ':white_check_mark:' : ':x:'
    end

    def latency_change(check)
      if check[:speedup_factor] < 0.8
        sprintf('%.1fx slower than %s', 1/check[:speedup_factor], job[:reference])
      elsif check[:speedup_factor] > 1.2
        sprintf('%.1fx faster than %s', check[:speedup_factor].abs, job[:reference])
      else
        "about the same as #{job[:reference]}"
      end << sprintf(' (%dms vs %dms)', check[:latency], check[:reference_latency])
    end

    def query_check_and_change(check)
      l = config.limits.queries
      if check[:query_count] < check[:reference_query_count] && check[:reference_query_count] >= l
        ":white_check_mark: Reduced AR queries from #{check[:reference_query_count]} to #{check[:query_count]}!"
      elsif check[:query_count] > check[:reference_query_count] && check[:query_count] >= l
        ":x: Increased AR queries from #{check[:reference_query_count]} to #{check[:query_count]}!"
      elsif check[:query_count] == check[:reference_query_count] && check[:reference_query_count] >= l
        ":warning: #{check[:query_count]} AR queries were made"
      end
    end

    def absolute_latency_check(check)
      if check[:latency] > config.limits.latency
        sprintf(":warning: Takes over %.1f seconds", config.limits.latency.to_f / 1000)
      end
    end
  end
end
