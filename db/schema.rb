# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_20_201539) do
  create_table "activity_logs", force: :cascade do |t|
    t.string "activity_type", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "message"
    t.json "metadata", default: {}
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["activity_type"], name: "index_activity_logs_on_activity_type"
    t.index ["user_id", "created_at"], name: "index_activity_logs_on_user_id_and_created_at"
    t.index ["user_id", "status", "updated_at"], name: "index_activity_logs_on_user_status_updated"
    t.index ["user_id"], name: "index_activity_logs_on_user_id"
  end

  create_table "api_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.datetime "last_used_at"
    t.string "name", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_api_tokens_on_user_id"
  end

  create_table "channel_content_events", force: :cascade do |t|
    t.integer "channel_content_id", null: false
    t.datetime "created_at", null: false
    t.integer "event_id", null: false
    t.datetime "updated_at", null: false
    t.index ["channel_content_id", "event_id"], name: "idx_on_channel_content_id_event_id_2970c519af", unique: true
    t.index ["channel_content_id"], name: "index_channel_content_events_on_channel_content_id"
    t.index ["event_id"], name: "index_channel_content_events_on_event_id"
  end

  create_table "channel_contents", force: :cascade do |t|
    t.integer "channel_id", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.text "generation_prompt"
    t.datetime "published_at"
    t.integer "status", default: 0, null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.json "version_history", default: []
    t.index ["channel_id", "created_at"], name: "index_channel_contents_on_channel_id_and_created_at"
    t.index ["channel_id", "status"], name: "index_channel_contents_on_channel_id_and_status"
    t.index ["channel_id"], name: "index_channel_contents_on_channel_id"
    t.index ["user_id"], name: "index_channel_contents_on_user_id"
  end

  create_table "channel_events", force: :cascade do |t|
    t.integer "channel_id", null: false
    t.datetime "created_at", null: false
    t.integer "event_id", null: false
    t.text "relevance_reason"
    t.integer "relevance_score"
    t.datetime "updated_at", null: false
    t.boolean "used", default: false, null: false
    t.datetime "used_at"
    t.index ["channel_id", "event_id"], name: "index_channel_events_on_channel_id_and_event_id", unique: true
    t.index ["channel_id", "relevance_score"], name: "index_channel_events_on_channel_id_and_relevance_score"
    t.index ["channel_id", "used", "relevance_score"], name: "index_channel_events_on_channel_used_relevance"
    t.index ["channel_id", "used"], name: "index_channel_events_on_channel_id_and_used"
    t.index ["channel_id"], name: "index_channel_events_on_channel_id"
    t.index ["event_id"], name: "index_channel_events_on_event_id"
  end

  create_table "channels", force: :cascade do |t|
    t.string "content_language"
    t.text "content_prompt"
    t.string "content_style"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "language", default: "en", null: false
    t.string "name", null: false
    t.text "prompt"
    t.json "settings", default: {}
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_channels_on_user_id"
  end

  create_table "dev_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "details", default: {}
    t.string "log_type", null: false
    t.text "message"
    t.bigint "parent_id"
    t.string "parent_type"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["parent_type", "parent_id"], name: "index_dev_logs_on_parent_type_and_parent_id"
    t.index ["user_id", "created_at"], name: "index_dev_logs_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_dev_logs_on_user_id"
  end

  create_table "event_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "event_id", null: false
    t.integer "link_type", default: 0, null: false
    t.integer "linked_content_id", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "linked_content_id"], name: "index_event_links_on_event_id_and_linked_content_id", unique: true
    t.index ["event_id"], name: "index_event_links_on_event_id"
    t.index ["linked_content_id"], name: "index_event_links_on_linked_content_id"
  end

  create_table "events", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.string "d_tag"
    t.datetime "embedded_at"
    t.binary "embedding"
    t.integer "event_type", default: 0, null: false
    t.string "external_id", null: false
    t.json "metadata", default: {}
    t.datetime "published_at", null: false
    t.json "raw_data", default: {}
    t.integer "source_id", null: false
    t.datetime "updated_at", null: false
    t.index ["external_id"], name: "index_events_on_external_id"
    t.index ["published_at"], name: "index_events_on_published_at"
    t.index ["source_id", "d_tag"], name: "index_events_on_source_id_and_d_tag"
    t.index ["source_id", "external_id"], name: "index_events_on_source_id_and_external_id", unique: true
    t.index ["source_id", "published_at"], name: "index_events_on_source_id_and_published_at"
    t.index ["source_id"], name: "index_events_on_source_id"
  end

  create_table "linked_contents", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.datetime "embedded_at"
    t.binary "embedding"
    t.datetime "fetched_at"
    t.json "metadata", default: {}
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["url"], name: "index_linked_contents_on_url", unique: true
  end

  create_table "nostr_auth_sessions", force: :cascade do |t|
    t.text "auth_url"
    t.string "authenticated_pubkey"
    t.string "authenticated_user_pubkey"
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.datetime "listener_started_at"
    t.string "listener_token"
    t.string "pending_rpc_id"
    t.string "relay_url", null: false
    t.string "secret", null: false
    t.string "session_id", null: false
    t.string "temp_privkey", null: false
    t.string "temp_pubkey", null: false
    t.datetime "updated_at", null: false
    t.index ["expires_at"], name: "index_nostr_auth_sessions_on_expires_at"
    t.index ["session_id"], name: "index_nostr_auth_sessions_on_session_id", unique: true
  end

  create_table "sources", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "distance", default: 5, null: false
    t.string "identifier", null: false
    t.string "name"
    t.json "settings", default: {}
    t.integer "source_type", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["identifier"], name: "index_sources_on_identifier"
    t.index ["user_id", "source_type", "identifier"], name: "index_sources_on_user_id_and_source_type_and_identifier", unique: true
    t.index ["user_id"], name: "index_sources_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.text "about"
    t.json "content_templates", default: []
    t.datetime "created_at", null: false
    t.text "default_content_style"
    t.string "display_name"
    t.datetime "last_reindexed_at"
    t.string "npub", null: false
    t.string "picture_url"
    t.string "pubkey_hex", null: false
    t.json "settings", default: {}
    t.text "system_prompt"
    t.datetime "updated_at", null: false
    t.string "username"
    t.index ["npub"], name: "index_users_on_npub", unique: true
    t.index ["pubkey_hex"], name: "index_users_on_pubkey_hex", unique: true
  end

  add_foreign_key "activity_logs", "users"
  add_foreign_key "api_tokens", "users"
  add_foreign_key "channel_content_events", "channel_contents"
  add_foreign_key "channel_content_events", "events"
  add_foreign_key "channel_contents", "channels"
  add_foreign_key "channel_contents", "users"
  add_foreign_key "channel_events", "channels"
  add_foreign_key "channel_events", "events"
  add_foreign_key "channels", "users"
  add_foreign_key "dev_logs", "users"
  add_foreign_key "event_links", "events"
  add_foreign_key "event_links", "linked_contents"
  add_foreign_key "events", "sources"
  add_foreign_key "sources", "users"
end
