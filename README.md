# perf_check_daemon

This repo contains:

1) A Sinatra app that receives webhooks from github

When a certain user is mentioned, it will fire off

2) A resque job that automates Rails performance testing via [perf_check](https://github.com/rubytune/perf_check).

3) A status app to view all jobs and their history.


### Usage

Call out to your user in a pull request comment (in the body, review, or diff), giving the urls to test, and shortly after you'll get a reply summarizing the performance differences between the branches:

![](https://cloud.githubusercontent.com/assets/6469642/13340018/cb4dd9c2-dbe1-11e5-98b7-8501b2512c70.png)

Any arguments you pass in are fed directly into perf_check. For example, this comment would run 3 different performance checks each with custom options:

```
Hit the /posts action 50 times:

@PerfCheckUser -n50 /posts

Test against /posts performance on a specific branch:

@PerfCheckUser -r this_other_branch /posts

Consider redirects as failures (default):

@PerfCheckUser --302-failure /posts
```

Three separate comments will be posted in reply. Please see the [perf_check readme](https://github.com/rubytune/perf_check) for information on its behavior and options.

### Setup

#### Prerequisites

1. Redis
2. To receive github webhook you'll need to be reachable at an external address/port combination.

####  Edit Config
Copy config/daemon.yml.example to config/daemon.yml, and fill in the appropriate values.

daemon.yml configuration:

| key |  |
|-----|---------|
app.path | Filesystem path to the rails app being perf check'd. The app should be setup to run in development mode, and have `gem "perf_check"` bundled.
credentials.user | User used for HTTP basic auth on /status page (optional).
credentials.password | Password used for HTTP basic auth on /status page (optional).
limits.change_factor | Factor of change in latency before a warning is added to the pull request comment.
limits.latency | Absolute response time allowed before a warning is added to the pull request comment.
limits.queries | Number of queries allowed before a warning is added to the pull request comment.
defaults | Default options for `perf_check`, e.g. `-n 50`
github.user | Name of the github user whose mention triggers a perf check.
github.hook_secret | Secret for github web hooks.
github.token | Github api token. Should be cleared for `repo`, `gist`, `notifications`, and `user` scopes.
redis.password | Redis password (optional).
redis.port | Redis port (default: 6379).
redis.host | Redis host (default: localhost).

#### Setup db

```
bundle exec rake db:create
```

### Webhooks

Add two web hooks to your github repository:

  * Aim `PullRequest` events at `http://example.com/pull_request`
  * Aim `IssueComment` and `PullRequestReviewComment` events at `http://example.com/comment`

You'll also need the github token mentioned in the config above.


### Running the app

#### Redis is needed

`brew install redis`

There are two components you'll need to daemonize:

  * The [sinatra app](https://github.com/wioux/perf_check_daemon/blob/master/lib/perf_check_daemon/app.rb) which listens for github web hooks
  * The [resque worker](https://github.com/wioux/perf_check_daemon/blob/master/lib/perf_check_daemon/job.rb) which will do the actual perf checking and post the results back to github.

Boot up the server with

`rackup -p 3000`


Boot up resque with

`bundle exec rake resque:work QUEUE=perf_check_jobs`


### Submit a test job

Here's an example job from github.com/sudara/alonetone

Boot into irb.

```
bundle exec racksh
```

```
job = {
  'arguments' => '/',
  'branch' => 'perf_check_test',
  'reference' => 'master',
  'sha' => 'd737e72513829611113d867f56334f5c4332bec4',
  'reference_sha' => 'abc',
  'pull_request' => 'https://github.com/sudara/alonetone/pull/129',
  'pull_request_comments' => 'https://github.com/sudara/alonetone/pull/129'
}
```

To submit this job using `racksh`, run

```
Resque.enqueue(PerfCheckDaemon::Job, job)
```

