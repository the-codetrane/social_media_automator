# The Spaces object key is the real identity of a media asset. Imports used to
# key assets on a hash of whatever URL string they were handed, so the same
# object reached through a differently-encoded URL ("Eagle's 34/Clip 1.mp4" vs
# "Eagle%27s%2034/Clip%201.mp4") or another host became a second row.
class AddStorageKeyToMediaAssets < ActiveRecord::Migration[8.1]
  class Asset < ActiveRecord::Base
    self.table_name = "media_assets"
  end

  def up
    add_column :media_assets, :storage_key, :string

    blob_keys = select_rows(<<~SQL).to_h
      SELECT a.record_id, b.key
      FROM active_storage_attachments a
      JOIN active_storage_blobs b ON b.id = a.blob_id
      WHERE a.record_type = 'MediaAsset' AND a.name = 'file'
    SQL

    taken = {}
    Asset.order(:id).find_each do |asset|
      key = blob_keys[asset.id] || MediaAsset.storage_key_from_metadata(asset.raw_metadata)
      next if key.blank?

      if taken[key]
        say "media_asset #{asset.id} duplicates #{taken[key]} (#{key}); leaving storage_key blank"
        next
      end

      taken[key] = asset.id
      asset.update_columns(storage_key: key)
    end

    add_index :media_assets, :storage_key, unique: true
  end

  def down
    remove_index :media_assets, :storage_key
    remove_column :media_assets, :storage_key
  end
end
