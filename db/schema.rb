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

ActiveRecord::Schema[8.1].define(version: 2026_07_28_120000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index [ "blob_id" ], name: "index_active_storage_attachments_on_blob_id"
    t.index [ "record_type", "record_id", "name", "blob_id" ], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index [ "key" ], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index [ "blob_id", "variation_digest" ], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "app_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.text "value"
    t.index [ "key" ], name: "index_app_settings_on_key", unique: true
  end

  create_table "chats", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "model_id"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index [ "model_id" ], name: "index_chats_on_model_id"
    t.index [ "user_id" ], name: "index_chats_on_user_id"
  end

  create_table "known_people", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.text "notes"
    t.string "reference_image_url"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index [ "user_id", "name" ], name: "index_known_people_on_user_id_and_name", unique: true
    t.index [ "user_id" ], name: "index_known_people_on_user_id"
  end

  create_table "media_assets", force: :cascade do |t|
    t.string "address"
    t.string "city"
    t.string "country"
    t.datetime "created_at", null: false
    t.float "duration_seconds"
    t.string "external_id", null: false
    t.string "external_name"
    t.bigint "file_size"
    t.datetime "first_seen_at", null: false
    t.integer "height"
    t.json "identified_people"
    t.datetime "identified_people_at"
    t.datetime "last_processed_at"
    t.float "latitude"
    t.float "longitude"
    t.integer "media_type", default: 0, null: false
    t.string "mime_type"
    t.json "raw_metadata"
    t.string "state"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "width"
    t.index [ "external_id" ], name: "index_media_assets_on_external_id", unique: true
    t.index [ "latitude", "longitude" ], name: "index_media_assets_on_latitude_and_longitude"
    t.index [ "media_type" ], name: "index_media_assets_on_media_type"
    t.index [ "status" ], name: "index_media_assets_on_status"
  end

  create_table "messages", force: :cascade do |t|
    t.integer "cache_creation_tokens"
    t.integer "cached_tokens"
    t.integer "chat_id", null: false
    t.text "content"
    t.json "content_raw"
    t.datetime "created_at", null: false
    t.integer "input_tokens"
    t.integer "model_id"
    t.integer "output_tokens"
    t.string "role", null: false
    t.text "thinking_signature"
    t.text "thinking_text"
    t.integer "thinking_tokens"
    t.integer "tool_call_id"
    t.datetime "updated_at", null: false
    t.index [ "chat_id" ], name: "index_messages_on_chat_id"
    t.index [ "model_id" ], name: "index_messages_on_model_id"
    t.index [ "role" ], name: "index_messages_on_role"
    t.index [ "tool_call_id" ], name: "index_messages_on_tool_call_id"
  end

  create_table "models", force: :cascade do |t|
    t.json "capabilities", default: []
    t.integer "context_window"
    t.datetime "created_at", null: false
    t.string "family"
    t.date "knowledge_cutoff"
    t.integer "max_output_tokens"
    t.json "metadata", default: {}
    t.json "modalities", default: {}
    t.datetime "model_created_at"
    t.string "model_id", null: false
    t.string "name", null: false
    t.json "pricing", default: {}
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.index [ "family" ], name: "index_models_on_family"
    t.index [ "provider", "model_id" ], name: "index_models_on_provider_and_model_id", unique: true
    t.index [ "provider" ], name: "index_models_on_provider"
  end

  create_table "planned_posts", force: :cascade do |t|
    t.json "cached_insights"
    t.text "caption"
    t.datetime "created_at", null: false
    t.string "external_post_id"
    t.string "hashtags"
    t.integer "media_asset_id", null: false
    t.integer "platform", null: false
    t.json "platform_payload"
    t.datetime "published_at"
    t.datetime "scheduled_at"
    t.integer "social_template_id"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index [ "media_asset_id" ], name: "index_planned_posts_on_media_asset_id"
    t.index [ "platform" ], name: "index_planned_posts_on_platform"
    t.index [ "scheduled_at" ], name: "index_planned_posts_on_scheduled_at"
    t.index [ "social_template_id" ], name: "index_planned_posts_on_social_template_id"
    t.index [ "status" ], name: "index_planned_posts_on_status"
    t.index [ "user_id" ], name: "index_planned_posts_on_user_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index [ "user_id" ], name: "index_sessions_on_user_id"
  end

  create_table "social_templates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "default_caption"
    t.integer "max_caption_length"
    t.string "name", null: false
    t.integer "platform", null: false
    t.string "recommended_aspect_ratio"
    t.json "settings"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index [ "platform", "name" ], name: "index_social_templates_on_platform_and_name", unique: true
    t.index [ "user_id" ], name: "index_social_templates_on_user_id"
  end

  create_table "tool_calls", force: :cascade do |t|
    t.json "arguments", default: {}
    t.datetime "created_at", null: false
    t.integer "message_id", null: false
    t.string "name", null: false
    t.text "thought_signature"
    t.string "tool_call_id", null: false
    t.datetime "updated_at", null: false
    t.index [ "message_id" ], name: "index_tool_calls_on_message_id"
    t.index [ "name" ], name: "index_tool_calls_on_name"
    t.index [ "tool_call_id" ], name: "index_tool_calls_on_tool_call_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "instagram_access_token"
    t.string "instagram_page_id"
    t.datetime "instagram_token_expires_at"
    t.string "instagram_user_id"
    t.string "instagram_username"
    t.string "name"
    t.string "password_digest", null: false
    t.string "tiktok_access_token"
    t.string "tiktok_open_id"
    t.datetime "tiktok_refresh_expires_at"
    t.string "tiktok_refresh_token"
    t.string "tiktok_scope"
    t.datetime "tiktok_token_expires_at"
    t.string "tiktok_username"
    t.datetime "updated_at", null: false
    t.index [ "email_address" ], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "chats", "models"
  add_foreign_key "chats", "users"
  add_foreign_key "known_people", "users"
  add_foreign_key "messages", "chats"
  add_foreign_key "messages", "models"
  add_foreign_key "messages", "tool_calls"
  add_foreign_key "planned_posts", "media_assets"
  add_foreign_key "planned_posts", "social_templates"
  add_foreign_key "planned_posts", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "social_templates", "users"
  add_foreign_key "tool_calls", "messages"
end
