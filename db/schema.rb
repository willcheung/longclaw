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

ActiveRecord::Schema.define(version: 20150702212857) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"
  enable_extension "uuid-ossp"

  create_table "accounts", id: :uuid, default: "uuid_generate_v4()", force: :cascade do |t|
    t.string   "name",            default: "", null: false
    t.text     "description",     default: ""
    t.string   "website"
    t.uuid     "owner_id"
    t.string   "phone"
    t.text     "address"
    t.uuid     "created_by"
    t.uuid     "updated_by"
    t.datetime "created_at",                   null: false
    t.datetime "updated_at",                   null: false
    t.uuid     "organization_id"
    t.text     "notes"
    t.string   "status"
  end

  create_table "clarizen_csv_import", id: false, force: :cascade do |t|
    t.date  "Reported Date"
    t.text  "Customers"
    t.text  "Name"
    t.text  "Project"
    t.text  "Work Item"
    t.float "Duration"
    t.text  "Comment"
    t.text  "Created By"
    t.text  "First Name"
    t.text  "Last Name"
  end

  create_table "contacts", id: :uuid, default: "uuid_generate_v4()", force: :cascade do |t|
    t.uuid     "account_id"
    t.string   "first_name", default: "", null: false
    t.string   "last_name",  default: "", null: false
    t.string   "email",      default: "", null: false
    t.string   "phone",      default: "", null: false
    t.string   "title",      default: "", null: false
    t.datetime "created_at",              null: false
    t.datetime "updated_at",              null: false
  end

  create_table "harvest_csv_import", id: false, force: :cascade do |t|
    t.date    "Date"
    t.string  "Client",          limit: 150
    t.string  "Project",         limit: 150
    t.string  "Project Code",    limit: 150
    t.string  "Task",            limit: 150
    t.string  "Notes",           limit: 150
    t.float   "Hours"
    t.string  "Billable?",       limit: 150
    t.string  "Invoiced?",       limit: 150
    t.string  "First Name",      limit: 150
    t.string  "Last Name",       limit: 150
    t.string  "Department",      limit: 150
    t.string  "Employee?",       limit: 150
    t.integer "Hourly Rate"
    t.integer "Billable Amount"
    t.string  "Currency",        limit: 150
  end

  create_table "organizations", id: :uuid, default: "uuid_generate_v4()", force: :cascade do |t|
    t.string   "name"
    t.string   "domain"
    t.boolean  "is_active",  default: true
    t.datetime "created_at",                null: false
    t.datetime "updated_at",                null: false
    t.uuid     "owner_id"
  end

  create_table "project_members", id: :uuid, default: "uuid_generate_v4()", force: :cascade do |t|
    t.uuid     "project_id"
    t.uuid     "contact_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "projects", id: :uuid, default: "uuid_generate_v4()", force: :cascade do |t|
    t.string   "name",               default: "",    null: false
    t.uuid     "account_id"
    t.string   "project_code"
    t.boolean  "is_billable",        default: true
    t.string   "status"
    t.text     "description"
    t.date     "planned_start_date"
    t.date     "planned_end_date"
    t.date     "actual_start_date"
    t.date     "actual_end_date"
    t.integer  "budgeted_hours"
    t.uuid     "created_by"
    t.uuid     "updated_by"
    t.uuid     "owner_id"
    t.boolean  "is_template",        default: false
    t.datetime "created_at",                         null: false
    t.datetime "updated_at",                         null: false
  end

  create_table "tasks", id: :uuid, default: "uuid_generate_v4()", force: :cascade do |t|
    t.uuid     "project_id"
    t.string   "name",            default: "",   null: false
    t.text     "description"
    t.integer  "assignee_id"
    t.string   "status"
    t.boolean  "is_billable",     default: true
    t.integer  "hourly_rate"
    t.string   "external_url"
    t.integer  "estimated_hours"
    t.integer  "external_id"
    t.text     "external_source"
    t.datetime "created_at",                     null: false
    t.datetime "updated_at",                     null: false
  end

  create_table "timesheet_entries", id: :uuid, default: "uuid_generate_v4()", force: :cascade do |t|
    t.uuid     "timesheet_id"
    t.uuid     "task_id"
    t.string   "notes"
    t.date     "date"
    t.decimal  "hours"
    t.datetime "created_at",   null: false
    t.datetime "updated_at",   null: false
  end

  create_table "timesheets", id: :uuid, default: "uuid_generate_v4()", force: :cascade do |t|
    t.uuid     "user_id"
    t.integer  "calendar_week"
    t.string   "year"
    t.string   "status"
    t.datetime "created_at",    null: false
    t.datetime "updated_at",    null: false
  end

  create_table "users", id: :uuid, default: "uuid_generate_v4()", force: :cascade do |t|
    t.string   "first_name",             default: "", null: false
    t.string   "last_name",              default: "", null: false
    t.string   "email",                  default: "", null: false
    t.string   "encrypted_password",     default: "", null: false
    t.string   "image_url"
    t.string   "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer  "sign_in_count",          default: 0,  null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.inet     "current_sign_in_ip"
    t.inet     "last_sign_in_ip"
    t.string   "oauth_provider"
    t.string   "oauth_provider_uid"
    t.string   "oauth_access_token"
    t.string   "oauth_refresh_token"
    t.datetime "oauth_expires_at"
    t.uuid     "organization_id"
    t.string   "department"
    t.integer  "hourly_rate"
    t.boolean  "is_billable"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "users", ["email"], name: "index_users_on_email", unique: true, using: :btree
  add_index "users", ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true, using: :btree

end
