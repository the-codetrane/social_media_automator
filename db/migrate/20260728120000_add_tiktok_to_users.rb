class AddTikTokToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :tiktok_open_id,            :string
    add_column :users, :tiktok_access_token,       :string
    add_column :users, :tiktok_token_expires_at,   :datetime
    add_column :users, :tiktok_refresh_token,      :string
    add_column :users, :tiktok_refresh_expires_at, :datetime
    add_column :users, :tiktok_username,           :string
    add_column :users, :tiktok_scope,              :string
  end
end
