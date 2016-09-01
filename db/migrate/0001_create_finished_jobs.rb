
require "perf_check_daemon/configure"

class CreateFinishedJobs < ActiveRecord::Migration
  def change
    create_table :finished_jobs do |t|
      t.string :issue_title
      t.string :issue_url
      t.string :branch
      t.string :github_user
      t.string :job_enqueued_at
      t.string :job_id

      t.string :arguments
      t.string :log_path

      t.timestamps
    end
  end
end

CreateFinishedJobs.migrate(:up)
