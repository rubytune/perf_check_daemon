#!/usr/bin/env ruby

require File.expand_path '../test_helper.rb', __FILE__

def config
  $APP_CONFIG ||= OpenStruct.new(
    defaults: '-n42',
    app: OpenStruct.new(path: 'application_path')
  )
end

class PerfCheckDaemonJobTest < MiniTest::Test
  attr_accessor :job, :perf_check_output

  def setup
    self.job = {
      'arguments' => '/path',
      'branch' => 'test_branch',
      'reference' => 'master',
      'sha' => '123',
      'reference_sha' => 'abc',
      'pull_request' => 'pull_request_url',
      'pull_request_comments' => 'pull_request_issue_comments_url'
    }

    self.perf_check_output = JSON.dump(
      [
        
      ]
    )
  end
end
