# perf_check_daemon
Watches pull requests on your github repository and comments on how the changes will affect your app's performance (using [perf_check](https://github.com/rubytune/perf_check)).

### Setup
#### Configuration
Copy config/daemon.yml.example to config/daemon.yml, and fill in the appropriate values.

daemon.yml configuration:

| key |  |
|-----|---------|
app.path | Filesystem path to the rails app being perf check'd. The app should be setup to run in development mode, and have `gem "perf_check"` bundled.
limits.change_factor | Factor of change in latency before a warning is added to the pull request comment.
limits.latency | Absolute response time allowed before a warning is added to the pull request comment.
limits.queries | Number of queries allowed before a warning is added to the pull request comment.
defaults | Default options for `perf_check`, e.g. `-n 50`
github.user | Name of the github user whose mention triggers a perf check.
github.hook_secret | Secret for github web hooks.
github.token | Github api token. Should be cleared for `repo`, `gist`, `notifications`, and `user` scopes.
redis.password | Redis password (optional).

Add two web hooks to your github repository:
  * Aim `PullRequest` events at `http://example.com/pull_request`
  * Aim `IssueComment` and `PullRequestReviewComment` events at `http://example.com/comment`

#### Running the app
There are two components you'll need to daemonize:
  * The [sinatra app](https://github.com/wioux/perf_check_daemon/blob/master/lib/perf_check_daemon/app.rb) which listens for github web hooks
  * The [resque worker](https://github.com/wioux/perf_check_daemon/blob/master/lib/perf_check_daemon/job.rb) which will do the actual perf checking and post the results back to github
