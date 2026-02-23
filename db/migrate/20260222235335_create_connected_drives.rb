class CreateConnectedDrives < ActiveRecord::Migration[8.1]
  def change
    create_table :connected_drives do |t|
      t.string  :name, null: false
      t.string  :provider, null: false, default: "google_drive"  # future‑proof
      t.string  :folder_id, null: false                          # Google Drive folder ID
      t.string  :account_email                                   # for display/debug
      t.string  :access_token
      t.string  :refresh_token
      t.datetime :token_expires_at

      t.integer :sync_interval_minutes, null: false, default: 60
      t.datetime :last_synced_at

      t.references :user, null: false, foreign_key: true         # owner/admin

      t.timestamps
    end
    add_index :connected_drives, [ :provider, :folder_id ], unique: true
  end
end
