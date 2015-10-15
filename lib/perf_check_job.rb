

require 'erb'
require 'shellwords'

require_relative "configure"

class PerfCheckJob
  @queue = :perf_check_jobs

  def self.perform(job)
    paths = sanitize_arguments(job.fetch('arguments'))

    app_path = Shellwords.escape(config.app.path)
    paths = Shellwords.split(paths).map{ |p| Shellwords.escape(p) }.join(' ')
    branch = Shellwords.escape(job.fetch('branch'))

    perf_check_output = Bundler.with_clean_env do
      JSON.parse(`cd #{app_path} &&
                  git fetch --all 1>&2 &&
                  git checkout #{branch} 1>&2 &&
                  git submodule update 1>&2 &&
                  git pull 1>&2 &&
                  git submodule update 1>&2 &&
                  bundle 1>&2 &&
                  bundle exec perf_check -jn3 #{paths}`)
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

  def self.sanitize_arguments(args)
    args.strip.split(/\s+/).reject do |arg|
      arg.strip.match(/^-/)
    end.join(' ')
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
  end
end
