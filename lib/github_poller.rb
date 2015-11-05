
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
    each_mention(object['body']) do |args|
      if timestamp + 3 < notification_timestamp
        log_disregarded_mention(timestamp, notification_timestamp, object['html_url'])
      else
        job_template[:arguments] = args
        jobs.push(job_template.dup)
      end
    end
  end

  def each_notification
    api("repos/#{github.repo}/notifications").each do |notification|
      next unless notification['reason'] == 'mention'
      next unless notification['subject']['type'] == 'PullRequest'

      yield notification
    end
  end

  def poll
    max_notification_time = nil

    each_notification do |notification|
      notification_time = Time.parse(notification['updated_at'])
      max_notification_time ||= notification_time
      max_notification_time = [max_notification_time, notification_time].max

      pull = api(notification['subject']['url'])

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
        comment_time = Time.parse(comment['updated_at'])
        scan_mentions(notification_time, comment_time, comment)
      end

      api(pull['review_comments_url']).each do |comment|
        job_template[:pull_request_comments] = pull['review_comments_url']
        job_template[:pull_request_comment_id] = comment['id']

        comment_time = Time.parse(comment['updated_at'])
        scan_mentions(notification_time, comment_time, comment)
      end
    end

    max_notification_time
  end

  def log_disregarded_mention(t, nt, url)
    logger.debug("Disregarding mention from #{t} (notification is #{nt}): #{url}")
  end
end
