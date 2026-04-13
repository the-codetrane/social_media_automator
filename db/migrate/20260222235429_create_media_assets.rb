class CreateMediaAssets < ActiveRecord::Migration[8.1]
  def change
    create_table :media_assets do |t|
      t.string  :external_id, null: false      # Google Drive file ID
      t.string  :external_name
      t.string  :mime_type
      t.bigint  :file_size

      t.integer :media_type, null: false, default: 0
      # enum media_type: { image: 0, video: 1 }

      t.integer :width
      t.integer :height
      t.float   :duration_seconds

      t.json :raw_metadata                      # full API response if needed

      t.integer :status, null: false, default: 0
      # enum status: { discovered: 0, processed: 1, failed: 2, archived: 3 }

      t.datetime :first_seen_at, null: false
      t.datetime :last_processed_at

      t.timestamps
    end
    add_index :media_assets, :external_id, unique: true
    add_index :media_assets, :status
    add_index :media_assets, :media_type
  end
end
