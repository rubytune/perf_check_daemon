# Load path and gems/bundler
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "bundler"
Bundler.require

require "perf_check_daemon/app"
run PerfCheckDaemon::App