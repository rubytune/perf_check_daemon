lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "perf_check_daemon/job"
require "sinatra/activerecord/rake"
require 'resque/tasks'

namespace :db do
  task :load_config do
    require "perf_check_daemon/app"
  end
end