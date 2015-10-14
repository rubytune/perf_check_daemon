# perf_check_daemon

#### `config/app.yml`
Config for the app being perf checked. Must have `path`, which is the filesystem path to the app repo.

#### `config/github.yml`
Needs `repo` and `user`. The repo will be polled for pull request notifications mentioning @user.

#### `config/secrets.yml`
Needs `github['token']` -- the auth token used in requests to the GitHub api.
