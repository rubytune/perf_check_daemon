
require "sinatra/base"
require "json"
require "openssl"

require "erubis"

require "perf_check_daemon/configure"
require "perf_check_daemon/job"
require "perf_check_daemon/github_comment"

module PerfCheckDaemon
  class App < Sinatra::Base
    HMAC_DIGEST = OpenSSL::Digest::Digest.new('sha1')

    attr_accessor :payload

    configure :production, :development do
      enable :logging
    end

    set :erb, :escape_html => true

    helpers do
      def time_ago_in_words(time)
        now = Time.now
        mins = (now - time.to_time) / 60.0
        case mins
        when 0...1
          sprintf("%d seconds ago", now - time.to_time)
        when 1...2
          "1 minute ago"
        when 2...60
          sprintf("%d minutes ago", mins)
        when 60...(24*60)
          sprintf("%.1f hours ago", mins/60.0)
        else
          sprintf("%.1f days ago", mins/60.0/24.0)
        end
      end
    end

    get "/" do
      "Hello World!"
    end

    # pull_request
    post "/pull_request" do
      pull = payload.fetch('pull_request')

      if payload.fetch('action') == 'opened'
        jobs = GithubComment.extract_jobs(pull, pull)
        jobs.each{ |job| Resque.enqueue(PerfCheckDaemon::Job, job) }
      end

      "Ok"
    end

    # pull_request_review_comment
    # issue_comment
    post "/comment" do
      if payload['issue'] && payload['issue'].key?('pull_request')
        pull = self.class.g(payload['issue']['pull_request']['url'])
      elsif payload['pull_request']
        pull = payload['pull_request']
      end

      comment = payload.fetch('comment')

      if payload.fetch('action') == 'created'
        jobs = GithubComment.extract_jobs(pull || payload["issue"], comment)
        jobs.each{ |job| Resque.enqueue(PerfCheckDaemon::Job, job) }
      end

      "Ok"
    end

    get "/status" do
      queue = PerfCheckDaemon::Job.queue.to_s

      @queued_jobs = [Resque.peek(queue, 0, Resque.size(queue))].flatten(1)

      @current_job = nil
      Resque.workers.map do |worker|
        if worker.working? && (job = worker.job)["queue"] == queue
          @current_job = job
        end
      end

      @failed_jobs = []
      [Resque::Failure.all(0, Resque::Failure.count)].flatten(1).compact.each do |failure|
        if failure["payload"]["class"] == "PerfCheckDaemon::Job"
          @failed_jobs << failure
        end
      end
      @failed_jobs.reverse!

      @current_job && @current_job.merge!(@current_job.delete("payload")["args"][0])
      @queued_jobs.each{ |j| j.merge!(j.delete("args")[0]) }
      @failed_jobs.each{ |j| j.merge!(j.delete("payload")["args"][0]) }

      @current_job && (@current_job["run_at"] = DateTime.parse(@current_job["run_at"]))
      @queued_jobs.each{ |j| j["created_at"] = DateTime.parse(j["created_at"]) }
      @failed_jobs.each{ |j| j["failed_at"] = DateTime.parse(j["failed_at"]) }

      erb :status, content_type: "text/html"
    end


    before /status/ do
      auth = Rack::Auth::Basic::Request.new(request.env)
      credentials = config.credentials
      credentials &&= [config.credentials.user, config.credentials.password]
      auth_basic = auth.provided? && auth.basic? && auth.credentials
      unless auth_basic && auth.credentials == credentials
        headers['WWW-Authenticate'] = 'Basic realm="Restricted Area"'
        halt 401, "Not authorized\n"
      end
    end

    before /pull_request|comment/ do
      body = request.body.read
      if secret = config.github.hook_secret
        digest = "sha1=#{OpenSSL::HMAC.hexdigest(HMAC_DIGEST, secret, body)}"
        if Rack::Utils.secure_compare(digest, request.env['HTTP_X_HUB_SIGNATURE'])
          @payload = JSON.parse(body)
        else
          warn "Warning: Signature does not match request digest. Dropping hook."
          halt 500, "Signatures didn't match!"
        end
      else
        @payload = JSON.parse(body)
      end
    end

    def self.g(*args)
      api(*args)
    end
  end
end
