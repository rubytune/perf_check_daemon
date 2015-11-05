#!/usr/bin/env ruby

require 'minitest/autorun'

require 'ostruct'
require 'shellwords'

require_relative '../lib/perf_check_job'

def config
  $APP_CONFIG ||= OpenStruct.new(
    defaults: '-n42',
    app: OpenStruct.new(path: 'application_path')
  )
end

class PerfCheckJobTest < MiniTest::Test
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

  def test_command_arguments_are_shell_escaped
    command = nil
    PerfCheckJob.stub(:capture, ->(x){ command = x; perf_check_output }) do
      PerfCheckJob.stub(:post_results, nil) do
        job['branch'] = '$escape_branch_name'
        config.defaults << '$escape_default_arguments'
        config.app.path << '$escape_application_path'

        funny_args = ["$(needs_escaping)", ">abc"]
        job['arguments'] << " #{funny_args.join(' ')}"

        PerfCheckJob.perform(job)

        assert_includes(command, Shellwords.escape(job['branch']))
        assert_includes(command, Shellwords.escape(config.defaults))
        assert_includes(command, Shellwords.escape(config.app.path))
        funny_args.each{ |arg| assert_includes(command, Shellwords.escape(arg)) }

        config.defaults.sub!(/\$escape_default_arguments$/, '')
        config.app.path.sub!(/\$escape_application_path$/, '')
      end
    end
  end
end