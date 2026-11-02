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

ActiveRecord::Schema[8.1].define(version: 2026_11_02_143208) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index [ "blob_id" ], name: "index_active_storage_attachments_on_blob_id"
    t.index [ "record_type", "record_id", "name", "blob_id" ], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index [ "key" ], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index [ "blob_id", "variation_digest" ], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "app_settings", force: :cascade do |t|
    t.string "key", null: false
    t.text "value"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "key" ], name: "index_app_settings_on_key", unique: true
  end

  create_table "chats", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "ruby_llm_model_id"
    t.integer "user_id"
    t.boolean "cancelled", default: false, null: false
    t.index [ "ruby_llm_model_id" ], name: "index_chats_on_ruby_llm_model_id"
    t.index [ "user_id" ], name: "index_chats_on_user_id"
  end

  create_table "known_people", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "name", null: false
    t.string "reference_image_url"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "user_id", "name" ], name: "index_known_people_on_user_id_and_name", unique: true
    t.index [ "user_id" ], name: "index_known_people_on_user_id"
  end

  create_table "media_assets", force: :cascade do |t|
    t.string "external_id", null: false
    t.string "external_name"
    t.string "mime_type"
    t.bigint "file_size"
    t.integer "media_type", default: 0, null: false
    t.integer "width"
    t.integer "height"
    t.float "duration_seconds"
    t.json "raw_metadata"
    t.integer "status", default: 0, null: false
    t.datetime "first_seen_at", null: false
    t.datetime "last_processed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "identified_people"
    t.datetime "identified_people_at"
    t.float "latitude"
    t.float "longitude"
    t.string "address"
    t.string "city"
    t.string "state"
    t.string "country"
    t.datetime "archived_at"
    t.datetime "published_at"
    t.index [ "archived_at" ], name: "index_media_assets_on_archived_at"
    t.index [ "external_id" ], name: "index_media_assets_on_external_id", unique: true
    t.index [ "latitude", "longitude" ], name: "index_media_assets_on_latitude_and_longitude"
    t.index [ "media_type" ], name: "index_media_assets_on_media_type"
    t.index [ "published_at" ], name: "index_media_assets_on_published_at"
    t.index [ "status" ], name: "index_media_assets_on_status"
  end

  create_table "messages", force: :cascade do |t|
    t.string "role", null: false
    t.text "content"
    t.text "thinking_text"
    t.text "thinking_signature"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "chat_id", null: false
    t.boolean "cache_until_here", default: false, null: false
    t.string "finish_reason"
    t.json "citations"
    t.json "server_tool_calls"
    t.json "raw_content"
    t.json "raw_reasoning"
    t.index [ "chat_id" ], name: "index_messages_on_chat_id"
  end

  create_table "planned_posts", force: :cascade do |t|
    t.integer "media_asset_id", null: false
    t.integer "social_template_id"
    t.integer "platform", null: false
    t.text "caption"
    t.string "hashtags"
    t.json "platform_payload"
    t.integer "status", default: 0, null: false
    t.datetime "scheduled_at"
    t.datetime "published_at"
    t.string "external_post_id"
    t.integer "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "cached_insights"
    t.index [ "media_asset_id" ], name: "index_planned_posts_on_media_asset_id"
    t.index [ "platform" ], name: "index_planned_posts_on_platform"
    t.index [ "scheduled_at" ], name: "index_planned_posts_on_scheduled_at"
    t.index [ "social_template_id" ], name: "index_planned_posts_on_social_template_id"
    t.index [ "status" ], name: "index_planned_posts_on_status"
    t.index [ "user_id" ], name: "index_planned_posts_on_user_id"
  end

  create_table "ruby_llm_batches", force: :cascade do |t|
    t.string "provider_batch_id", null: false
    t.string "provider", null: false
    t.string "status", null: false
    t.string "raw_status"
    t.boolean "completed", default: false, null: false
    t.string "chat_type"
    t.string "batch_protocol"
    t.json "chat_ids", default: []
    t.json "request_counts"
    t.json "reported_cost"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "provider", "provider_batch_id" ], name: "index_ruby_llm_batches_on_provider_and_provider_batch_id", unique: true
    t.index [ "status" ], name: "index_ruby_llm_batches_on_status"
  end

  create_table "ruby_llm_models", force: :cascade do |t|
    t.string "model_id", null: false
    t.string "name", null: false
    t.string "provider", null: false
    t.string "family"
    t.datetime "model_created_at"
    t.integer "context_window"
    t.integer "max_output_tokens"
    t.date "knowledge_cutoff"
    t.json "modalities", default: {}
    t.json "capabilities", default: []
    t.json "pricing", default: {}
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "unlisted_at"
    t.index [ "family" ], name: "index_ruby_llm_models_on_family"
    t.index [ "provider", "model_id" ], name: "index_ruby_llm_models_on_provider_and_model_id", unique: true
    t.index [ "provider" ], name: "index_ruby_llm_models_on_provider"
  end

  create_table "ruby_llm_tool_calls", force: :cascade do |t|
    t.string "tool_call_id", null: false
    t.string "name", null: false
    t.text "thought_signature"
    t.json "arguments", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "message_id", null: false
    t.string "message_type", null: false
    t.string "result_type"
    t.integer "result_id"
    t.string "approval"
    t.boolean "remote", default: false, null: false
    t.index [ "message_type", "message_id" ], name: "index_ruby_llm_tool_calls_on_message_type_and_message_id"
    t.index [ "name" ], name: "index_ruby_llm_tool_calls_on_name"
    t.index [ "result_type", "result_id" ], name: "index_ruby_llm_tool_calls_on_result_type_and_result_id"
    t.index [ "tool_call_id" ], name: "index_ruby_llm_tool_calls_on_tool_call_id", unique: true
  end

  create_table "ruby_llm_usages", force: :cascade do |t|
    t.string "chat_type", null: false
    t.integer "chat_id", null: false
    t.string "message_type"
    t.integer "message_id"
    t.string "operation", null: false
    t.string "provider", null: false
    t.string "model", null: false
    t.string "status", null: false
    t.integer "input_tokens"
    t.integer "output_tokens"
    t.integer "cache_read_tokens"
    t.integer "cache_write_tokens"
    t.integer "thinking_tokens"
    t.decimal "input_cost", precision: 16, scale: 10
    t.decimal "output_cost", precision: 16, scale: 10
    t.decimal "cache_read_cost", precision: 16, scale: 10
    t.decimal "cache_write_cost", precision: 16, scale: 10
    t.decimal "thinking_cost", precision: 16, scale: 10
    t.decimal "total_cost", precision: 16, scale: 10
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "chat_type", "chat_id" ], name: "index_ruby_llm_usages_on_chat_type_and_chat_id"
    t.index [ "message_type", "message_id" ], name: "index_ruby_llm_usages_on_message_type_and_message_id"
    t.index [ "status" ], name: "index_ruby_llm_usages_on_status"
    t.check_constraint "operation IN ('chat', 'embedding', 'moderation', 'image', 'speech', 'transcription', 'ocr', 'rerank')"
    t.check_constraint "status IN ('pending', 'succeeded', 'failed', 'cancelled')"
  end

  create_table "sessions", force: :cascade do |t|
    t.integer "user_id", null: false
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "user_id" ], name: "index_sessions_on_user_id"
  end

  create_table "social_templates", force: :cascade do |t|
    t.integer "platform", null: false
    t.string "name", null: false
    t.text "default_caption"
    t.integer "max_caption_length"
    t.string "recommended_aspect_ratio"
    t.json "settings"
    t.integer "user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "platform", "name" ], name: "index_social_templates_on_platform_and_name", unique: true
    t.index [ "user_id" ], name: "index_social_templates_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.string "name"
    t.string "instagram_user_id"
    t.string "instagram_access_token"
    t.datetime "instagram_token_expires_at"
    t.string "instagram_page_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "instagram_username"
    t.boolean "admin", default: false, null: false
    t.string "tiktok_open_id"
    t.string "tiktok_access_token"
    t.datetime "tiktok_token_expires_at"
    t.string "tiktok_refresh_token"
    t.datetime "tiktok_refresh_expires_at"
    t.string "tiktok_username"
    t.string "tiktok_scope"
    t.string "tiktok_environment"
    t.index [ "email_address" ], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "chats", "ruby_llm_models"
  add_foreign_key "chats", "users"
  add_foreign_key "known_people", "users"
  add_foreign_key "messages", "chats"
  add_foreign_key "planned_posts", "media_assets"
  add_foreign_key "planned_posts", "social_templates"
  add_foreign_key "planned_posts", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "social_templates", "users"
end
