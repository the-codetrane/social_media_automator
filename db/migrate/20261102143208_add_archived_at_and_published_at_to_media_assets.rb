class AddArchivedAtAndPublishedAtToMediaAssets < ActiveRecord::Migration[8.1]
  # Former MediaAsset.status values, frozen here so the migration does not
  # depend on the model's enum (which no longer has :archived).
  PROCESSED = 1
  ARCHIVED  = 3
  PUBLISHED_POST = 2

  def up
    add_column :media_assets, :archived_at, :datetime
    add_column :media_assets, :published_at, :datetime
    add_index :media_assets, :archived_at
    add_index :media_assets, :published_at

    # Archiving moves off the processing-status enum onto its own timestamp.
    execute <<~SQL
      UPDATE media_assets
      SET archived_at = updated_at, status = #{PROCESSED}
      WHERE status = #{ARCHIVED}
    SQL

    # Stamp every asset already used by a published post — the primary asset
    # and any carousel members — with the earliest time it went out.
    execute <<~SQL
      UPDATE media_assets
      SET published_at = (
        SELECT MIN(COALESCE(pp.published_at, pp.updated_at))
        FROM planned_posts pp
        WHERE pp.status = #{PUBLISHED_POST}
          AND (
            pp.media_asset_id = media_assets.id
            OR (
              json_valid(pp.platform_payload)
              AND EXISTS (
                SELECT 1
                FROM json_each(pp.platform_payload, '$.carousel_asset_ids') AS carousel_ids
                WHERE CAST(carousel_ids.value AS INTEGER) = media_assets.id
              )
            )
          )
      )
      WHERE published_at IS NULL
    SQL
  end

  def down
    execute <<~SQL
      UPDATE media_assets SET status = #{ARCHIVED} WHERE archived_at IS NOT NULL
    SQL

    remove_index :media_assets, :published_at
    remove_index :media_assets, :archived_at
    remove_column :media_assets, :published_at
    remove_column :media_assets, :archived_at
  end
end
