
require 'sqlite3'

module PerfCheckDaemon
  class GithubPoller
    attr_reader :github, :jobs, :job_template

    def initialize(config)
      @github = config
      @jobs = []
    end

    def each_mention(text)
      text.scan(/^@#{github.user} (.+)/).each do |args|
        yield(args.first)
      end
    end

    def scan_mentions(notification_timestamp, timestamp, object)
      return unless new_mention?(object)

      job_template[:github_holder] = object
      each_mention(object['body']) do |args|
        job_template[:arguments] = args
        jobs.push(job_template.dup)
      end
    end

    def each_notification
      api("repos/#{github.repo}/notifications").each do |notification|
        next unless notification['reason'] == 'mention'
        next unless notification['subject']['type'] == 'PullRequest'

        yield notification
      end
    end

    def scan_pull_request(notification_time, id: nil, url: nil)
      if url
        pull = api(url)
      else
        pull = api("repos/#{github.repo}/pulls/#{id}")
      end

      @job_template = {
        pull_request: pull['url'],
        pull_request_comments: pull['comments_url'],
        branch: pull['head']['ref'],
        reference: pull['base']['ref'],
        sha: pull['head']['sha'],
        reference_sha: pull['base']['sha']
      }

      pull_time = Time.parse(pull['created_at'])
      scan_mentions(notification_time, pull_time, pull)

      api(pull['comments_url']).each do |comment|
        comment_time = Time.parse(comment['created_at'])
        scan_mentions(notification_time, comment_time, comment)
      end

      api(pull['review_comments_url']).each do |comment|
        job_template[:pull_request_comments] = pull['review_comments_url']
        job_template[:pull_request_comment_id] = comment['id']

        comment_time = Time.parse(comment['created_at'])
        scan_mentions(notification_time, comment_time, comment)
      end
    end

    def poll
      max_notification_time = nil

      each_notification do |notification|
        notification_time = Time.parse(notification['updated_at'])
        max_notification_time ||= notification_time
        max_notification_time = [max_notification_time, notification_time].max

        scan_pull_request(notification_time, url: notification['subject']['url'])
      end

      max_notification_time
    end

    def db
      @db ||=
        begin
          dbfile = File.expand_path("../../../db/notifications.sqlite3", __FILE__)
          SQLite3::Database.new(dbfile).tap do |db|
            db.execute <<-SQL
            CREATE TABLE IF NOT EXISTS notifications (
              github_url varchar(250),
              arguments text,
              timestamp datetime
            );
          SQL
          end
        end
    end

    def new_mention?(holder)
      github_url = holder.fetch('url')
      timestamp = holder.fetch('created_at')

      sql, binds = "select count(*) from notifications where github_url = ?", [github_url]
      app_logger.debug([sql, binds].inspect)
      count = db.execute(sql, binds)[0][0]
      count.zero?
    end

    def log_mention(holder, args)
      github_url = holder.fetch('url')
      timestamp = holder.fetch('created_at')

      sql = "insert into notifications (github_url, arguments, timestamp) values (?, ?, ?)"
      binds = github_url, args.strip, timestamp
      app_logger.debug([sql, binds].inspect)
      db.execute(sql, binds)
    end
  end
end
