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

ActiveRecord::Schema.define(version: 20160817000158) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"
  enable_extension "uuid-ossp"

  create_table "accounts", id: :uuid, default: "uuid_generate_v4()", force: :cascade do |t|
    t.string   "name",                       default: "",         null: false
    t.text     "description",                default: ""
    t.string   "website"
    t.uuid     "owner_id"
    t.string   "phone"
    t.text     "address"
    t.uuid     "created_by"
    t.uuid     "updated_by"
    t.datetime "created_at",                                      null: false
    t.datetime "updated_at",                                      null: false
    t.uuid     "organization_id"
    t.text     "notes"
    t.string   "status",                     default: "Active"
    t.string   "domain",          limit: 64, default: "",         null: false
    t.string   "category",                   default: "Customer"
    t.datetime "deleted_at"
    t.string   "salesforce_id",              default: ""
  end

  add_index "accounts", ["deleted_at"], name: "index_accounts_on_deleted_at", using: :btree

  create_table "activities", force: :cascade do |t|
    t.string   "category",                             null: false
    t.string   "title",                                null: false
    t.text     "note",                 default: "",    null: false
    t.boolean  "is_public",            default: true,  null: false
    t.string   "backend_id"
    t.datetime "last_sent_date"
    t.string   "last_sent_date_epoch"
    t.jsonb    "from",                 default: [],    null: false
    t.jsonb    "to",                   default: [],    null: false
    t.jsonb    "cc",                   default: [],    null: false
    t.jsonb    "email_messages",       default: [],    null: false
    t.uuid     "project_id",                           null: false
    t.uuid     "posted_by",                            null: false
    t.datetime "created_at",                           null: false
    t.datetime "updated_at",                           null: false
    t.boolean  "is_pinned",            default: false
    t.uuid     "pinned_by"
    t.datetime "pinned_at"
  end

  add_index "activities", ["category", "backend_id", "project_id"], name: "index_activities_on_category_and_backend_id_and_project_id", unique: true, using: :btree
  add_index "activities", ["email_messages"], name: "index_activities_on_email_messages", using: :gin
  add_index "activities", ["project_id"], name: "index_activities_on_project_id", using: :btree

  create_table "ahoy_events", id: :uuid, default: nil, force: :cascade do |t|
    t.uuid     "visit_id"
    t.uuid     "user_id"
    t.string   "name"
    t.jsonb    "properties"
    t.datetime "time"
  end

  add_index "ahoy_events", ["time"], name: "index_ahoy_events_on_time", using: :btree
  add_index "ahoy_events", ["user_id"], name: "index_ahoy_events_on_user_id", using: :btree
  add_index "ahoy_events", ["visit_id"], name: "index_ahoy_events_on_visit_id", using: :btree

  create_table "ahoy_messages", force: :cascade do |t|
    t.string   "token"
    t.text     "to"
    t.uuid     "user_id"
    t.string   "user_type"
    t.string   "mailer"
    t.text     "subject"
    t.text     "content"
    t.datetime "sent_at"
    t.datetime "opened_at"
    t.datetime "clicked_at"
  end

  add_index "ahoy_messages", ["token"], name: "index_ahoy_messages_on_token", using: :btree
  add_index "ahoy_messages", ["user_id", "user_type"], name: "index_ahoy_messages_on_user_id_and_user_type", using: :btree

  create_table "comments", force: :cascade do |t|
    t.string   "title",            limit: 50, default: ""
    t.text     "comment"
    t.integer  "commentable_id"
    t.string   "commentable_type"
    t.uuid     "user_id"
    t.string   "role",                        default: "comments"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "comments", ["commentable_id"], name: "index_comments_on_commentable_id", using: :btree
  add_index "comments", ["commentable_type"], name: "index_comments_on_commentable_type", using: :btree
  add_index "comments", ["user_id"], name: "index_comments_on_user_id", using: :btree

  create_table "contacts", id: :uuid, default: "uuid_generate_v4()", force: :cascade do |t|
    t.uuid     "account_id"
    t.string   "first_name",                 default: "", null: false
    t.string   "last_name",                  default: "", null: false
    t.string   "email",                      default: "", null: false
    t.string   "phone",           limit: 32, default: "", null: false
    t.string   "title",                      default: "", null: false
    t.datetime "created_at",                              null: false
    t.datetime "updated_at",                              null: false
    t.string   "alt_email"
    t.string   "mobile",          limit: 32
    t.text     "background_info"
    t.string   "department"
  end

  add_index "contacts", ["account_id"], name: "index_contacts_on_account_id", using: :btree

  create_table "notifications", force: :cascade do |t|
    t.string   "category",          default: "To-do", null: false
    t.string   "name"
    t.text     "description"
    t.string   "message_id"
    t.uuid     "project_id"
    t.string   "conversation_id"
    t.datetime "sent_date"
    t.datetime "original_due_date"
    t.datetime "remind_date"
    t.boolean  "is_complete",       default: false,   null: false
    t.boolean  "has_time",          default: false,   null: false
    t.integer  "content_offset",    default: -1,      null: false
    t.datetime "complete_date"
    t.uuid     "assign_to"
    t.uuid     "completed_by"
    t.string   "label"
    t.datetime "created_at",                          null: false
    t.datetime "updated_at",                          null: false
    t.float    "score",             default: 0.0
  end

  create_table "oauth_users", force: :cascade do |t|
    t.uuid     "organization_id",                  null: false
    t.datetime "created_at",                       null: false
    t.datetime "updated_at",                       null: false
    t.string   "oauth_key",           default: ""
    t.string   "oauth_id",            default: ""
    t.string   "oauth_provider_uid",  default: ""
    t.string   "oauth_user_name",     default: ""
    t.string   "oauth_provider",      default: ""
    t.string   "oauth_access_token",  default: ""
    t.string   "oauth_instance_url",  default: ""
    t.string   "oauth_refresh_token", default: ""
  end

  add_index "oauth_users", ["oauth_provider", "oauth_user_name", "oauth_instance_url"], name: "oauth_per_user", unique: true, using: :btree
  add_index "oauth_users", ["organization_id"], name: "index_oauth_users_on_organization_id", using: :btree

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
    t.uuid     "user_id"
  end

  add_index "project_members", ["contact_id"], name: "index_project_members_on_contact_id", using: :btree
  add_index "project_members", ["project_id"], name: "index_project_members_on_project_id", using: :btree
  add_index "project_members", ["user_id"], name: "index_project_members_on_user_id", using: :btree

  create_table "project_subscribers", force: :cascade do |t|
    t.uuid     "project_id"
    t.uuid     "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_index "project_subscribers", ["project_id"], name: "index_project_subscribers_on_project_id", using: :btree
  add_index "project_subscribers", ["user_id"], name: "index_project_subscribers_on_email", using: :btree

  create_table "projects", id: :uuid, default: "uuid_generate_v4()", force: :cascade do |t|
    t.string   "name",           default: "",               null: false
    t.uuid     "account_id"
    t.string   "project_code"
    t.boolean  "is_public",      default: true
    t.string   "status",         default: "Active"
    t.text     "description"
    t.date     "start_date"
    t.date     "end_date"
    t.integer  "budgeted_hours"
    t.uuid     "created_by"
    t.uuid     "updated_by"
    t.uuid     "owner_id"
    t.datetime "created_at",                                null: false
    t.datetime "updated_at",                                null: false
    t.boolean  "is_confirmed"
    t.string   "category",       default: "Implementation"
    t.datetime "deleted_at"
  end

  add_index "projects", ["account_id"], name: "index_projects_on_account_id", using: :btree
  add_index "projects", ["deleted_at"], name: "index_projects_on_deleted_at", using: :btree

  create_table "users", id: :uuid, default: "uuid_generate_v4()", force: :cascade do |t|
    t.string   "first_name",                       default: "",    null: false
    t.string   "last_name",                        default: "",    null: false
    t.string   "email",                            default: "",    null: false
    t.string   "encrypted_password",               default: "",    null: false
    t.string   "image_url"
    t.string   "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer  "sign_in_count",                    default: 0,     null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.inet     "current_sign_in_ip"
    t.inet     "last_sign_in_ip"
    t.string   "oauth_provider"
    t.string   "oauth_provider_uid"
    t.string   "oauth_access_token"
    t.datetime "oauth_expires_at"
    t.uuid     "organization_id"
    t.string   "department"
    t.boolean  "is_disabled"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.datetime "invitation_created_at"
    t.uuid     "invited_by_id"
    t.integer  "onboarding_step"
    t.datetime "cluster_create_date"
    t.datetime "cluster_update_date"
    t.string   "title"
    t.string   "time_zone",                        default: "UTC"
    t.string   "encrypted_oauth_refresh_token",    default: ""
    t.string   "encrypted_oauth_refresh_token_iv", default: ""
    t.string   "oauth_refresh_token",              default: ""
  end

  add_index "users", ["email"], name: "index_users_on_email", unique: true, using: :btree
  add_index "users", ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true, using: :btree

  create_table "visits", id: :uuid, default: nil, force: :cascade do |t|
    t.uuid     "visitor_id"
    t.string   "ip"
    t.text     "user_agent"
    t.text     "referrer"
    t.text     "landing_page"
    t.uuid     "user_id"
    t.string   "referring_domain"
    t.string   "search_keyword"
    t.string   "browser"
    t.string   "os"
    t.string   "device_type"
    t.integer  "screen_height"
    t.integer  "screen_width"
    t.string   "country"
    t.string   "region"
    t.string   "city"
    t.string   "postal_code"
    t.decimal  "latitude"
    t.decimal  "longitude"
    t.string   "utm_source"
    t.string   "utm_medium"
    t.string   "utm_term"
    t.string   "utm_content"
    t.string   "utm_campaign"
    t.datetime "started_at"
  end

  add_index "visits", ["user_id"], name: "index_visits_on_user_id", using: :btree

end
