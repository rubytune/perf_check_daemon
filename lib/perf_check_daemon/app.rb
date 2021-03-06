
require "sinatra/base"
require "json"

require "erubis"

require "perf_check_daemon/configure"
require "perf_check_daemon/job"
require "perf_check_daemon/finished_job"
require "sinatra/activerecord"


module PerfCheckDaemon
  class App < Sinatra::Base
    register Sinatra::ActiveRecordExtension
    set :database, ActiveRecord::Base.connection_config

    HMAC_DIGEST = OpenSSL::Digest::Digest.new('sha1')

    attr_accessor :payload
    set :root, File.expand_path("#{File.dirname(__FILE__)}/../..")

    get "/" do
      redirect '/status'
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

    ["/comment","/pull_request"].each do |action|
      before action do
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
    end

    def self.g(*args)
      api(*args)
    end
  end
end
