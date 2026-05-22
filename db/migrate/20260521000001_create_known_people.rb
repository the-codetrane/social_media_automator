class CreateKnownPeople < ActiveRecord::Migration[8.1]
  def change
    create_table :known_people do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.string :reference_image_url, null: false
      t.text :notes

      t.timestamps
    end

    add_index :known_people, [ :user_id, :name ], unique: true
  end
end
