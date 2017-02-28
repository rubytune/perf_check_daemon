# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20170228032154) do

  create_table "finished_jobs", force: :cascade do |t|
    t.string   "issue_title"
    t.string   "issue_url"
    t.string   "branch"
    t.string   "github_user"
    t.string   "job_enqueued_at"
    t.string   "job_id"
    t.string   "arguments"
    t.string   "log_path"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.boolean  "failed"
    t.text     "details"
  end

end
