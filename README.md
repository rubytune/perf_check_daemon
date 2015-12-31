# perf_check_daemon

#### Setup
Copy config/daemon.yml.example to config/daemon.yml, and fill in the appropriate values.

daemon.yml configuration:
  * `app.path` - Filesystem path to the rails app being perf check'd. The app should be setup to run in development mode, and have `gem "perf_check"` bundled.
  * `defaults` - Default options for `perf_check`.
  * `github.hook_secret`- Secret for github web hooks.
  * `github.repo` - Name of the github repo to watch.
  * `github.token` - Github api token. Should be cleared for `repo`, `gist`, `notifications`, and `user` scopes.
  * `github.user` - Name of the github user whose mention triggers a perf check.
  * `limits.change_factor` - Factor of change in latency before a warning is added to the pull request comment.
  * `limits.latency` - Absolute response time allowed before a warning is added to the pull request comment.
  * `limits.queries` - Number of queries allowed before a warning is added to the pull request comment.
  * `redis.password` - Redis password, if needed (optional).

Add two web hooks to your github repository:
  * Aim `PullRequest` events at `http://example.com/pull_request`
  * Aim `IssueComment` and `PullRequestReviewComment` events at `http://example.com/comment`
