class AddInstagramCredentialsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :instagram_user_id, :string
    add_column :users, :instagram_access_token, :string
    add_column :users, :instagram_token_expires_at, :datetime
    add_column :users, :instagram_page_id, :string
  end
end
