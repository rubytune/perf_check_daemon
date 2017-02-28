class AddFailedAndDetailsToFinishedJobs < ActiveRecord::Migration
  def change
    add_column :finished_jobs, :failed, :boolean
    add_column :finished_jobs, :details, :text
  end
end
