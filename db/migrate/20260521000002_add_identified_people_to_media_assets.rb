class AddIdentifiedPeopleToMediaAssets < ActiveRecord::Migration[8.1]
  def change
    add_column :media_assets, :identified_people, :json
    add_column :media_assets, :identified_people_at, :datetime
  end
end
