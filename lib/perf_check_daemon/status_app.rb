require "sinatra/base"
require "json"
require "openssl"

require "erubis"

require "perf_check_daemon/configure"
require "perf_check_daemon/job"
require "perf_check_daemon/github_comment"

module PerfCheckDaemon
  class StatusApp < Sinatra::Base
    configure :production, :development do
      enable :logging
    end

    set :root, File.expand_path("#{File.dirname(__FILE__)}/../..")
    set :erb, :escape_html => true

    helpers do
      def resque_online?
        Resque.info[:workers] > 0
      end
      
      def markdown(text)
        text.gsub!(/:white_check_mark:/,'<i class="fa fa-check-square" aria-hidden="true"></i>')
        text.gsub!(/:warning:/,'<i class="fa fa-exclamation-triangle" aria-hidden="true"></i>')
        text.gsub!(/:x:/,'<i class="fa fa-times-circle" aria-hidden="true"></i>')
        Kramdown::Document.new(text, input: 'GFM', hard_wrap: true).to_html
      end

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
          sprintf("%dh %dm ago", mins/60, mins % 60)
        else
          sprintf("%1d day ago", (mins/60.0/24).to_i)
        end
      end

      def job_matches_query?(job, query)
        if query.is_a?(String)
          [
            job["github_holder"]["user"]["login"],
            job["issue_title"],
            job["branch"]
          ].any?{ |f| f.downcase[query.downcase] }
        elsif query.is_a?(Hash)
          PerfCheckDaemon::Job.id(DateTime.parse(job["created_at"])) == query[:id]
        else
          true
        end
      end

      def queued_jobs(query, queue=PerfCheckDaemon::Job.queue.to_s)
        queued = []
        [Resque.peek(queue, 0, Resque.size(queue))].flatten(1).each do |job|
          job = job["args"][0]

          next unless job_matches_query?(job, query)

          created_at = DateTime.parse(job["created_at"])
          queued.push(
            arguments: job["arguments"],
            queued: true,
            issue_title: job["issue_title"],
            issue_url: job["issue_html_url"],
            branch: job["branch"],
            github_user: job["github_holder"]["user"]["login"],
            enqueued_at: created_at
          )
        end

        queued
      end

      def current_jobs(query, queue=PerfCheckDaemon::Job.queue.to_s)
        current = []
        Resque.workers.map do |worker|
          if worker.working? && (job = worker.job)["queue"] == queue
            job = job["payload"]["args"][0]

            next unless job_matches_query?(job, query)

            created_at = DateTime.parse(job["created_at"])
            current.push(
              arguments: job["arguments"],
              current: true,
              issue_title: job["issue_title"],
              issue_url: job["issue_html_url"],
              branch: job["branch"],
              github_user: job["github_holder"]["user"]["login"],
              enqueued_at: created_at
            )
          end
        end

        current
      end

      def failed_jobs(query)
        failed = []
        [Resque::Failure.all(0, Resque::Failure.count)].flatten(1).compact.each do |failure|
          if failure["payload"]["class"] == "PerfCheckDaemon::Job"
            job = failure["payload"]["args"][0]

            next unless job_matches_query?(job, query)
            
            created_at = DateTime.parse(job["created_at"])
            failed.push(
              arguments: job["arguments"],
              failed: true,
              issue_title: job["issue_title"],
              issue_url: job["issue_html_url"],
              branch: job["branch"],
              github_user: job["github_holder"]["user"]["login"],
              enqueued_at: created_at
            )

            break if !query && failed.size > 25
          end
        end
        failed
      end

      def completed_jobs(query)
        if query.is_a?(String)
          scope = FinishedJob.where(
            "issue_title LIKE ?
            OR branch LIKE ?
            OR github_user LIKE ?",
            "%#{query}%", "%#{query}%", "%#{query}%"
          )
        elsif query.is_a?(Hash)
          scope = FinishedJob.where(job_id: query[:id])
        else
          scope = FinishedJob.limit(25)
        end

        scope.order("created_at DESC").map do |job|
          {
            arguments: job.arguments,
            complete: !job.failed?,
            issue_title: job.issue_title,
            issue_url: job.issue_url,
            branch: job.branch,
            github_user: job.github_user,
            enqueued_at: job.enqueued_at,
            details: job.details
          }
        end
      end

      def search_results(query=nil)
        query = nil unless "#{query}".match(/\S/)

        queued = queued_jobs(query)
        current = current_jobs(query)
        failed = failed_jobs(query)
        complete = completed_jobs(query)

        jobs = current
        jobs.concat queued.sort_by{ |j| j[:enqueued_at] }
        jobs.concat (complete + failed).sort_by{ |j| j[:enqueued_at] }.reverse

        jobs.each do |job|
          job[:id] = PerfCheckDaemon::Job.id(job[:enqueued_at])
          job[:url] = "/status/#{job[:id]}"
        end

        # jobs.unshift(html: "Most recent jobs:") unless query || jobs.empty ?
        # jobs
      rescue Redis::CannotConnectError
        halt 500, "Cannot connect to redis server"
      end
    end

    get "/service-info.json" do
      content_type :json

      JSON.generate({resque_online: resque_online?})
    end

    get "/search.json" do
      content_type :json
      search_results = self.search_results(params["f"])

      JSON.generate(results: search_results)
    end

    get "/" do
      @search_results = search_results(params["f"])      
      erb :status, layout: :layout, content_type: "text/html"
    end

    get "/:job_id" do
      @search_results = search_results(params["f"])
      @job = search_results(id: params["job_id"])[0]

      layout = request.xhr? ? nil : :layout
      erb :job_status, layout: layout, content_type: "text/html"
    end

    before // do
      if config.credentials
        auth = Rack::Auth::Basic::Request.new(request.env)
        credentials = config.credentials
        credentials &&= [config.credentials.user, config.credentials.password]
        auth_basic = auth.provided? && auth.basic? && auth.credentials
        unless auth_basic && auth.credentials == credentials
          headers['WWW-Authenticate'] = 'Basic realm="Restricted Area"'
          halt 401, "Not authorized\n"
        end
      end
    end
  end
end
