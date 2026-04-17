class AddInstagramUsernameToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :instagram_username, :string
  end
end
