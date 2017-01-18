# Load path and gems/bundler
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "bundler"
Bundler.require

require 'bugsnag'
require "perf_check_daemon/app"
require "perf_check_daemon/status_app"

use Bugsnag::Rack
set :raise_errors, true
set :show_exceptions, ENV['RACK_ENV'] == 'test'

map("/"){ run PerfCheckDaemon::App }
map("/status"){ run PerfCheckDaemon::StatusApp }
