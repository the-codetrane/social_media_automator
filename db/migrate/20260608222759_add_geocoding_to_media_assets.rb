class AddGeocodingToMediaAssets < ActiveRecord::Migration[8.1]
  def change
    add_column :media_assets, :latitude, :float
    add_column :media_assets, :longitude, :float
    add_column :media_assets, :address, :string
    add_column :media_assets, :city, :string
    add_column :media_assets, :state, :string
    add_column :media_assets, :country, :string
    add_index :media_assets, [ :latitude, :longitude ]
  end
end
