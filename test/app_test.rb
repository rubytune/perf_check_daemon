
require File.expand_path '../test_helper.rb', __FILE__

config.github.hook_secret = nil

class AppTest < MiniTest::Unit::TestCase
  include Rack::Test::Methods

  def app
    PerfCheckDaemon::App
  end

  def payload
    @payload ||= {
      action: '...',
      pull_request: {
        url: '...',
        comments_url: '...',
        head: { ref: '...', sha: '...' },
        base: { ref: '...', sha: '...' },
        body: "..."
      }
    }
  end

  def mention
    @mention ||= "@#{github.user} -n10 /abc"
  end

  def test_get_root
    get '/'

    assert last_response.ok?
    assert_equal "Hello World!", last_response.body
  end

  def test_post_opened_pull_request
    enqueued_jobs = []
    Resque.stub :enqueue, ->(*args){ enqueued_jobs << args } do
      payload[:action] = 'opened'

      # When there is no mention, no jobs are enqueued
      post "/pull_request", payload.to_json
      assert_equal 0, enqueued_jobs.size

      # Otherwise a job should be enqueued for each mention in the pull request body
      payload[:pull_request][:body] = [mention, mention].join("\n")
      post "/pull_request", payload.to_json
      assert_equal 2, enqueued_jobs.size
    end
  end

  def test_post_nonopened_pull_request
    enqueued_jobs = []
    Resque.stub :enqueue, ->(*args){ enqueued_jobs << args } do
      payload[:action] = 'reopened'

      # For non-"opened" pull request hooks, no jobs are enqueued regardless of mentions
      post "/pull_request", payload.to_json
      assert_equal 0, enqueued_jobs.size

      payload[:pull_request][:body] = [mention, mention].join("\n")
      post "/pull_request", payload.to_json
      assert_equal 0, enqueued_jobs.size
    end
  end

  def test_post_pull_request_review_comment
    enqueued_jobs = []
    Resque.stub :enqueue, ->(*args){ enqueued_jobs << args } do
      payload[:comment] = { }
      payload[:action] = "created"

      # When there is no mention, no jobs are enqueued
      payload[:comment][:body] = '...'
      post "/comment", payload.to_json
      assert_equal 0, enqueued_jobs.size

      # Otherwise, a job is enqueued for each mention in the comment body
      payload[:comment][:body] = [mention, mention].join("\n")
      post "/comment", payload.to_json
      assert_equal 2, enqueued_jobs.size

      enqueued_jobs.clear
      payload[:action] = "updated"
      post "/comment", payload.to_json
      assert_equal 0, enqueued_jobs.size
    end
  end

  def test_post_issue_comment
    enqueued_jobs = []
    Resque.stub :enqueue, ->(*args){ enqueued_jobs << args } do
      payload[:issue] = payload.delete(:pull_request)
      payload[:comment] = {}

      app.stub :api, ->(*_){ JSON.parse(payload[:issue].to_json) } do
        payload[:action] = "created"

        # A job is enqueued for each mention
        payload[:comment][:body] = [mention, mention].join("\n")
        post "/comment", payload.to_json
        assert_equal 2, enqueued_jobs.size
        enqueued_jobs.clear

        payload[:issue][:pull_request] = { url: '...' }
        post "/comment", payload.to_json
        assert_equal 2, enqueued_jobs.size
        enqueued_jobs.clear

        payload[:action] = "updated"
        post "/comment", payload.to_json
        assert_equal 0, enqueued_jobs.size

        payload[:action] = "created"
        payload[:comment][:body] = '...'
        post "/comment", payload.to_json
        assert_equal 0, enqueued_jobs.size
      end
    end
  end
end
