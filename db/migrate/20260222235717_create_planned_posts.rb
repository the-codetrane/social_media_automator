class CreatePlannedPosts < ActiveRecord::Migration[8.1]
  def change
    create_table :planned_posts do |t|
      t.references :media_asset, null: false, foreign_key: true
      t.references :social_template, foreign_key: true

      t.integer :platform, null: false
      # enum platform: { instagram: 0, youtube: 1, facebook: 2 }

      t.text    :caption
      t.string  :hashtags
      t.json  :platform_payload        # calculated payload (e.g., for API)

      t.integer :status, null: false, default: 0
      # enum status: { draft: 0, scheduled: 1, published: 2, failed: 3, canceled: 4 }

      t.datetime :scheduled_at
      t.datetime :published_at
      t.string   :external_post_id       # id returned by IG/YT/FB

      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
    add_index :planned_posts, :platform
    add_index :planned_posts, :status
    add_index :planned_posts, :scheduled_at
  end
end
