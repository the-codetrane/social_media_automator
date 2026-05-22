class MakeKnownPersonReferenceImageUrlOptional < ActiveRecord::Migration[8.1]
  def change
    change_column_null :known_people, :reference_image_url, true
  end
end
