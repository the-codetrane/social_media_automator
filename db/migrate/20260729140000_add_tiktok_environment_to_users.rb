class AddTikTokEnvironmentToUsers < ActiveRecord::Migration[8.1]
  def change
    # Which TikTok app (production or sandbox) issued the stored token.
    # Tokens are not interchangeable between the two.
    add_column :users, :tiktok_environment, :string
  end
end
