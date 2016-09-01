
require "active_record"

class FinishedJob < ActiveRecord::Base
  def enqueued_at
    DateTime.parse(job_enqueued_at)
  end
end
