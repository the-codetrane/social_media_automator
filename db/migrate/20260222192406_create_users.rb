class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.string :name

      t.string   :instagram_user_id
      t.string   :instagram_access_token
      t.datetime :instagram_token_expires_at
      t.string   :instagram_page_id

      t.timestamps
    end
    add_index :users, :email_address, unique: true
  end
end
