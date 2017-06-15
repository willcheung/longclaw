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

ActiveRecord::Schema.define(version: 20170614211922) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"
  enable_extension "hstore"
  enable_extension "uuid-ossp"

  create_table "accounts", id: :uuid, default: "uuid_generate_v4()", force: :cascade do |t|
    t.string   "name",                                                  default: "",         null: false
    t.text     "description",                                           default: ""
    t.string   "website"
    t.uuid     "owner_id"
    t.string   "phone"
    t.text     "address"
    t.uuid     "created_by"
    t.uuid     "updated_by"
    t.datetime "created_at",                                                                 null: false
    t.datetime "updated_at",                                                                 null: false
    t.uuid     "organization_id"
    t.text     "notes"
    t.string   "status",                                                default: "Active"
    t.string   "domain",            limit: 64,                          default: "",         null: false
    t.string   "category",                                              default: "Customer"
    t.datetime "deleted_at"
    t.decimal  "revenue_potential",            precision: 14, scale: 2
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
    t.integer  "rag_score"
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
    t.string   "first_name",                    default: "", null: false
    t.string   "last_name",                     default: "", null: false
    t.string   "email",                         default: "", null: false
    t.string   "phone",              limit: 32, default: "", null: false
    t.string   "title",                         default: "", null: false
    t.datetime "created_at",                                 null: false
    t.datetime "updated_at",                                 null: false
    t.string   "source"
    t.string   "mobile",             limit: 32
    t.text     "background_info"
    t.string   "department"
    t.string   "external_source_id"
    t.string   "buyer_role"
  end

  add_index "contacts", ["account_id", "email"], name: "index_contacts_on_account_id_and_email", unique: true, using: :btree
  add_index "contacts", ["account_id"], name: "index_contacts_on_account_id", using: :btree

  create_table "custom_configurations", force: :cascade do |t|
    t.uuid     "organization_id",              null: false
    t.uuid     "user_id"
    t.string   "config_type",                  null: false
    t.string   "config_value",    default: "", null: false
    t.datetime "created_at",                   null: false
    t.datetime "updated_at",                   null: false
  end

  add_index "custom_configurations", ["organization_id", "user_id", "config_type"], name: "idx_custom_configurations", unique: true, using: :btree

  create_table "custom_fields", force: :cascade do |t|
    t.uuid     "organization_id",           null: false
    t.integer  "custom_fields_metadata_id", null: false
    t.string   "customizable_type",         null: false
    t.uuid     "customizable_uuid",         null: false
    t.string   "value"
    t.datetime "created_at",                null: false
    t.datetime "updated_at",                null: false
  end

  add_index "custom_fields", ["customizable_type", "customizable_uuid"], name: "index_custom_fields_on_customizable_type_and_customizable_uuid", using: :btree
  add_index "custom_fields", ["organization_id", "custom_fields_metadata_id"], name: "custom_fields_idx", using: :btree

  create_table "custom_fields_metadata", force: :cascade do |t|
    t.uuid     "organization_id",          null: false
    t.string   "entity_type",              null: false
    t.string   "name",                     null: false
    t.string   "data_type",                null: false
    t.string   "update_permission_role",   null: false
    t.datetime "created_at",               null: false
    t.datetime "updated_at",               null: false
    t.string   "default_value"
    t.integer  "custom_lists_metadata_id"
    t.string   "salesforce_field"
  end

  add_index "custom_fields_metadata", ["custom_lists_metadata_id"], name: "index_custom_fields_metadata_on_custom_lists_metadata_id", using: :btree
  add_index "custom_fields_metadata", ["organization_id", "entity_type", "salesforce_field"], name: "idx_custom_fields_metadata_on_sf_field_and_entity_unique", unique: true, using: :btree
  add_index "custom_fields_metadata", ["organization_id", "entity_type"], name: "custom_fields_metadata_idx", using: :btree

  create_table "custom_lists", force: :cascade do |t|
    t.integer  "custom_lists_metadata_id", null: false
    t.string   "option_value",             null: false
    t.datetime "created_at",               null: false
    t.datetime "updated_at",               null: false
  end

  add_index "custom_lists", ["custom_lists_metadata_id"], name: "index_custom_lists_on_custom_lists_metadata_id", using: :btree

  create_table "custom_lists_metadata", force: :cascade do |t|
    t.uuid     "organization_id",                 null: false
    t.string   "name",                            null: false
    t.boolean  "cs_app_list",     default: false, null: false
    t.datetime "created_at",                      null: false
    t.datetime "updated_at",                      null: false
  end

  add_index "custom_lists_metadata", ["organization_id", "name"], name: "index_custom_lists_metadata_on_organization_id_and_name", using: :btree

  create_table "entity_fields_metadata", force: :cascade do |t|
    t.uuid     "organization_id",          null: false
    t.string   "entity_type",              null: false
    t.string   "name",                     null: false
    t.string   "default_value"
    t.integer  "custom_lists_metadata_id"
    t.string   "salesforce_field"
    t.string   "read_permission_role",     null: false
    t.string   "update_permission_role",   null: false
    t.datetime "created_at",               null: false
    t.datetime "updated_at",               null: false
  end

  add_index "entity_fields_metadata", ["organization_id", "entity_type"], name: "entity_fields_metadata_idx", using: :btree

  create_table "integrations", force: :cascade do |t|
    t.uuid     "contextsmith_account_id"
    t.integer  "external_account_id"
    t.uuid     "project_id"
    t.string   "external_source"
    t.datetime "created_at",              null: false
    t.datetime "updated_at",              null: false
    t.integer  "oauth_user_id"
  end

  add_index "integrations", ["oauth_user_id"], name: "index_integrations_on_oauth_user_id", using: :btree

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
    t.integer  "activity_id",       default: -1
  end

  create_table "oauth_users", force: :cascade do |t|
    t.string   "oauth_provider",                   null: false
    t.string   "oauth_provider_uid",               null: false
    t.string   "oauth_access_token",               null: false
    t.string   "oauth_refresh_token"
    t.string   "oauth_instance_url",               null: false
    t.string   "oauth_user_name",     default: "", null: false
    t.uuid     "organization_id",                  null: false
    t.datetime "created_at",                       null: false
    t.datetime "updated_at",                       null: false
    t.integer  "oauth_refresh_date"
    t.datetime "oauth_issued_date"
    t.uuid     "user_id"
  end

  add_index "oauth_users", ["oauth_provider", "oauth_user_name", "oauth_instance_url", "organization_id", "user_id"], name: "oauth_per_user", unique: true, using: :btree

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
    t.datetime "created_at",                       null: false
    t.datetime "updated_at",                       null: false
    t.uuid     "user_id"
    t.integer  "status",     limit: 2, default: 1, null: false
  end

  add_index "project_members", ["contact_id"], name: "index_project_members_on_contact_id", using: :btree
  add_index "project_members", ["project_id"], name: "index_project_members_on_project_id", using: :btree
  add_index "project_members", ["user_id"], name: "index_project_members_on_user_id", using: :btree

  create_table "project_subscribers", force: :cascade do |t|
    t.uuid     "project_id"
    t.uuid     "user_id"
    t.datetime "created_at",                null: false
    t.datetime "updated_at",                null: false
    t.boolean  "daily",      default: true, null: false
    t.boolean  "weekly",     default: true, null: false
  end

  add_index "project_subscribers", ["project_id"], name: "index_project_subscribers_on_project_id", using: :btree
  add_index "project_subscribers", ["user_id"], name: "index_project_subscribers_on_email", using: :btree

  create_table "projects", id: :uuid, default: "uuid_generate_v4()", force: :cascade do |t|
    t.string   "name",                                         default: "",            null: false
    t.uuid     "account_id"
    t.boolean  "is_public",                                    default: true
    t.string   "status",                                       default: "Active"
    t.text     "description"
    t.uuid     "created_by"
    t.uuid     "updated_by"
    t.uuid     "owner_id"
    t.datetime "created_at",                                                           null: false
    t.datetime "updated_at",                                                           null: false
    t.boolean  "is_confirmed"
    t.string   "category",                                     default: "Opportunity"
    t.datetime "deleted_at"
    t.date     "renewal_date"
    t.date     "contract_start_date"
    t.date     "contract_end_date"
    t.decimal  "contract_arr",        precision: 14, scale: 2
    t.integer  "renewal_count"
    t.boolean  "has_case_study",                               default: false,         null: false
    t.boolean  "is_referenceable",                             default: false,         null: false
    t.decimal  "amount",              precision: 14, scale: 2
    t.string   "stage"
    t.date     "close_date"
    t.decimal  "expected_revenue",    precision: 14, scale: 2
  end

  add_index "projects", ["account_id"], name: "index_projects_on_account_id", using: :btree
  add_index "projects", ["deleted_at"], name: "index_projects_on_deleted_at", using: :btree

  create_table "risk_settings", force: :cascade do |t|
    t.float    "medium_threshold"
    t.float    "high_threshold"
    t.float    "weight"
    t.boolean  "notify_task"
    t.boolean  "notify_email"
    t.integer  "metric"
    t.uuid     "level_id",                        null: false
    t.string   "level_type",                      null: false
    t.datetime "created_at",                      null: false
    t.datetime "updated_at",                      null: false
    t.boolean  "is_positive",      default: true, null: false
  end

  add_index "risk_settings", ["level_type", "level_id"], name: "index_risk_settings_on_level_type_and_level_id", using: :btree
  add_index "risk_settings", ["metric", "is_positive", "level_type", "level_id"], name: "idx_risk_settings_uniq", unique: true, using: :btree

  create_table "salesforce_accounts", force: :cascade do |t|
    t.string   "salesforce_account_id",        default: "", null: false
    t.string   "salesforce_account_name",      default: "", null: false
    t.datetime "salesforce_updated_at"
    t.uuid     "contextsmith_account_id"
    t.uuid     "contextsmith_organization_id",              null: false
    t.datetime "created_at",                                null: false
    t.datetime "updated_at",                                null: false
  end

  add_index "salesforce_accounts", ["salesforce_account_id"], name: "index_salesforce_accounts_on_salesforce_account_id", unique: true, using: :btree

  create_table "salesforce_opportunities", force: :cascade do |t|
    t.string   "salesforce_opportunity_id",                          default: "", null: false
    t.string   "salesforce_account_id",                              default: "", null: false
    t.string   "name",                                               default: "", null: false
    t.text     "description"
    t.decimal  "amount",                    precision: 14, scale: 2
    t.boolean  "is_closed"
    t.boolean  "is_won"
    t.string   "stage_name"
    t.date     "close_date"
    t.datetime "created_at",                                                      null: false
    t.datetime "updated_at",                                                      null: false
    t.uuid     "contextsmith_project_id"
    t.decimal  "probability",               precision: 5,  scale: 2
    t.decimal  "expected_revenue",          precision: 14, scale: 2
  end

  add_index "salesforce_opportunities", ["salesforce_opportunity_id"], name: "index_salesforce_opportunities_on_salesforce_opportunity_id", unique: true, using: :btree

  create_table "users", id: :uuid, default: "uuid_generate_v4()", force: :cascade do |t|
    t.string   "first_name",             default: "",    null: false
    t.string   "last_name",              default: "",    null: false
    t.string   "email",                  default: "",    null: false
    t.string   "encrypted_password",     default: "",    null: false
    t.string   "image_url"
    t.string   "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer  "sign_in_count",          default: 0,     null: false
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
    t.boolean  "is_disabled",            default: false, null: false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.datetime "invitation_created_at"
    t.uuid     "invited_by_id"
    t.integer  "onboarding_step"
    t.datetime "cluster_create_date"
    t.datetime "cluster_update_date"
    t.string   "title"
    t.string   "time_zone",              default: "UTC"
    t.boolean  "mark_private",           default: false, null: false
    t.string   "role"
    t.boolean  "refresh_inbox",          default: true,  null: false
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

  add_foreign_key "integrations", "oauth_users"
end
