#!/usr/bin/env ruby

require 'minitest/autorun'

require 'ostruct'
require 'logger'

require_relative '../lib/github_poller'

$NOTIFICATION = {
  'reason' => 'mention',
  'subject' => { 'type' => 'PullRequest', 'url' => 'pull_request' },
  'updated_at' => '2014-11-07T22:01:45Z',
}

$PULL_REQUEST = {
  'created_at' => '2014-11-07T22:01:45Z',
  'url' => 'pull_request_url',
  'head' => { 'ref' => 'branch', 'sha' => '123' },
  'base' => { 'ref' => 'master', 'sha' => 'abc' },
  'body' => '',
  'comments_url' => 'issue_comments',
  'review_comments_url' => 'review_comments'
}

$PR_COMMENT = {
  'updated_at' => '2014-11-07T22:01:45Z',
  'body' => ''
}

$DIFF_COMMENT = {
  'id' => 123,
  'updated_at' => '2014-11-07T22:01:45Z',
  'body' => ''
}

def api(path, *args)
  case path
  when /^repos\/.*\/notifications$/
    unless args[-1].is_a?(Hash) && args[-1].key?(:put)
      [$NOTIFICATION]
    end

  when "pull_request"
    $PULL_REQUEST.dup

  when 'issue_comments'
    [$PR_COMMENT]

  when 'review_comments'
    [$DIFF_COMMENT]

  end
end

def logger(*args)
  Logger.new('/dev/null')
end

class GithubPollerTest < MiniTest::Test
  attr_accessor :poller, :github

  def setup
    self.github = OpenStruct.new(repo: 'github_poller_test', user: 'PerfCheckDaemon')
    self.poller = GithubPoller.new(github)
  end

  def test_pull_request_mention
    $PULL_REQUEST['body'] = 'no mentions'
    poller.poll

    assert_equal 0, poller.jobs.size
    poller.jobs.clear

    $PULL_REQUEST['body'] = '@PerfCheckDaemon -n5 /opening_mention'
    poller.poll

    assert_equal 1, poller.jobs.size

    job = poller.jobs.shift
    assert_equal $PULL_REQUEST['url'], job.delete(:pull_request)
    assert_equal $PULL_REQUEST['comments_url'], job.delete(:pull_request_comments)
    assert_equal $PULL_REQUEST['head']['ref'], job.delete(:branch)
    assert_equal $PULL_REQUEST['base']['ref'], job.delete(:reference)
    assert_equal $PULL_REQUEST['head']['sha'], job.delete(:sha)
    assert_equal $PULL_REQUEST['base']['sha'], job.delete(:reference_sha)
    assert_equal '-n5 /opening_mention', job.delete(:arguments)

    $PULL_REQUEST['created_at'] = (Time.parse($NOTIFICATION['updated_at'])-3600).iso8601
    poller.poll

    assert_equal 0, poller.jobs.size

    $PULL_REQUEST['created_at'] = $NOTIFICATION['updated_at']
    $PULL_REQUEST['body'] = ''
  end

  def test_pull_request_comment_mention
    $PR_COMMENT['body'] = 'no mentions'
    poller.poll

    assert_equal 0, poller.jobs.size
    poller.jobs.clear

    $PR_COMMENT['body'] = '@PerfCheckDaemon -n5 /comment_mention'
    poller.poll

    assert_equal 1, poller.jobs.size

    job = poller.jobs.shift
    assert_equal $PULL_REQUEST['url'], job.delete(:pull_request)
    assert_equal $PULL_REQUEST['comments_url'], job.delete(:pull_request_comments)
    assert_equal $PULL_REQUEST['head']['ref'], job.delete(:branch)
    assert_equal $PULL_REQUEST['base']['ref'], job.delete(:reference)
    assert_equal $PULL_REQUEST['head']['sha'], job.delete(:sha)
    assert_equal $PULL_REQUEST['base']['sha'], job.delete(:reference_sha)
    assert_equal '-n5 /comment_mention', job.delete(:arguments)

    $PR_COMMENT['updated_at'] = (Time.parse($NOTIFICATION['updated_at'])-3600).iso8601
    poller.poll

    assert_equal 0, poller.jobs.size

    $PR_COMMENT['updated_at'] = $NOTIFICATION['updated_at']

    $PR_COMMENT['body'] = ''
  end

  def test_pull_request_diff_mention
    $DIFF_COMMENT['body'] = 'no mentions'
    poller.poll

    assert_equal 0, poller.jobs.size
    poller.jobs.clear

    $DIFF_COMMENT['body'] = '@PerfCheckDaemon -n5 /diff_mention'
    poller.poll

    assert_equal 1, poller.jobs.size

    job = poller.jobs.shift
    assert_equal $PULL_REQUEST['url'], job.delete(:pull_request)
    assert_equal 'review_comments', job.delete(:pull_request_comments)
    assert_equal $PULL_REQUEST['head']['ref'], job.delete(:branch)
    assert_equal $PULL_REQUEST['base']['ref'], job.delete(:reference)
    assert_equal $PULL_REQUEST['head']['sha'], job.delete(:sha)
    assert_equal $PULL_REQUEST['base']['sha'], job.delete(:reference_sha)
    assert_equal '-n5 /diff_mention', job.delete(:arguments)

    $DIFF_COMMENT['updated_at'] = (Time.parse($NOTIFICATION['updated_at'])-3600).iso8601
    poller.poll

    assert_equal 0, poller.jobs.size

    $DIFF_COMMENT['updated_at'] = $NOTIFICATION['updated_at']

    $DIFF_COMMENT['body'] = ''
  end
end
