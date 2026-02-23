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

ActiveRecord::Schema[8.1].define(version: 2026_02_23_000434) do
  create_table "connected_drives", force: :cascade do |t|
    t.string "access_token"
    t.string "account_email"
    t.datetime "created_at", null: false
    t.string "folder_id", null: false
    t.datetime "last_synced_at"
    t.string "name", null: false
    t.string "provider", default: "google_drive", null: false
    t.string "refresh_token"
    t.integer "sync_interval_minutes", default: 60, null: false
    t.datetime "token_expires_at"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["provider", "folder_id"], name: "index_connected_drives_on_provider_and_folder_id", unique: true
    t.index ["user_id"], name: "index_connected_drives_on_user_id"
  end

  create_table "media_assets", force: :cascade do |t|
    t.integer "connected_drive_id", null: false
    t.datetime "created_at", null: false
    t.float "duration_seconds"
    t.string "external_id", null: false
    t.string "external_name"
    t.bigint "file_size"
    t.datetime "first_seen_at", null: false
    t.integer "height"
    t.datetime "last_processed_at"
    t.integer "media_type", default: 0, null: false
    t.string "mime_type"
    t.json "raw_metadata"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "width"
    t.index ["connected_drive_id"], name: "index_media_assets_on_connected_drive_id"
    t.index ["external_id"], name: "index_media_assets_on_external_id", unique: true
    t.index ["media_type"], name: "index_media_assets_on_media_type"
    t.index ["status"], name: "index_media_assets_on_status"
  end

  create_table "planned_posts", force: :cascade do |t|
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
    t.index ["media_asset_id"], name: "index_planned_posts_on_media_asset_id"
    t.index ["platform"], name: "index_planned_posts_on_platform"
    t.index ["scheduled_at"], name: "index_planned_posts_on_scheduled_at"
    t.index ["social_template_id"], name: "index_planned_posts_on_social_template_id"
    t.index ["status"], name: "index_planned_posts_on_status"
    t.index ["user_id"], name: "index_planned_posts_on_user_id"
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
    t.index ["platform", "name"], name: "index_social_templates_on_platform_and_name", unique: true
    t.index ["user_id"], name: "index_social_templates_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  add_foreign_key "connected_drives", "users"
  add_foreign_key "media_assets", "connected_drives", column: "connected_drive_id"
  add_foreign_key "planned_posts", "media_assets"
  add_foreign_key "planned_posts", "social_templates"
  add_foreign_key "planned_posts", "users"
  add_foreign_key "social_templates", "users"
end
