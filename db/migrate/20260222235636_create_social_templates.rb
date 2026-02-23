class CreateSocialTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :social_templates do |t|
      t.integer :platform, null: false
      # enum platform: { instagram: 0, youtube: 1, facebook: 2 }

      t.string  :name, null: false
      t.text    :default_caption
      t.integer :max_caption_length
      t.string  :recommended_aspect_ratio        # e.g. "9:16", "1:1"

      t.json  :settings                        # platform‑specific flags

      t.references :user, foreign_key: true      # owner

      t.timestamps
    end
    add_index :social_templates, [:platform, :name], unique: true
  end
end
