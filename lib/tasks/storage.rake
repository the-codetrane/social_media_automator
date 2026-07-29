# frozen_string_literal: true

namespace :storage do
  desc "Migrate existing static map images into the Map Images/ folder in DigitalOcean Spaces"
  task migrate_map_images: :environment do
    attachments = ActiveStorage::Attachment.where(name: "static_map_image").includes(:blob)

    puts "#{attachments.count} static map image(s) found"

    migrated = 0
    skipped  = 0
    errors   = 0

    attachments.find_each do |attachment|
      blob    = attachment.blob
      old_key = blob.key

      if old_key.start_with?("Map Images/")
        puts "  [blob #{blob.id}] already in Map Images/ — skipping"
        skipped += 1
        next
      end

      new_key = "Map Images/#{old_key}"
      service = blob.service

      begin
        service.upload(
          new_key,
          StringIO.new(service.download(old_key)),
          checksum: blob.checksum,
          content_type: blob.content_type
        )

        if service.exist?(new_key)
          blob.update_column(:key, new_key)
          service.delete(old_key)
          migrated += 1
          puts "  [blob #{blob.id}] #{old_key} → #{new_key}"
        else
          puts "  [blob #{blob.id}] upload to #{new_key} could not be verified — skipping delete"
          errors += 1
        end
      rescue => e
        puts "  [blob #{blob.id}] error: #{e.message}"
        errors += 1
      end
    end

    puts "\nDone. #{migrated} migrated, #{skipped} already in place, #{errors} error(s)."
  end

  desc "Migrate existing chat-uploaded media files into the Images From Chat/ folder in DigitalOcean Spaces"
  task migrate_chat_images: :environment do
    attachments = ActiveStorage::Attachment
      .where(name: "file", record_type: "MediaAsset")
      .includes(:blob)
      .select { |a| !a.blob.key.include?("/") }

    puts "#{attachments.size} root-level chat image(s) found"

    migrated = 0
    skipped  = 0
    errors   = 0

    attachments.each do |attachment|
      blob    = attachment.blob
      old_key = blob.key

      if old_key.include?("/")
        puts "  [blob #{blob.id}] already in a folder — skipping"
        skipped += 1
        next
      end

      new_key = "Images From Chat/#{old_key}"
      service = blob.service

      begin
        service.upload(
          new_key,
          StringIO.new(service.download(old_key)),
          checksum: blob.checksum,
          content_type: blob.content_type
        )

        if service.exist?(new_key)
          blob.update_column(:key, new_key)
          service.delete(old_key)
          migrated += 1
          puts "  [blob #{blob.id}] #{old_key} → #{new_key}"
        else
          puts "  [blob #{blob.id}] upload to #{new_key} could not be verified — skipping delete"
          errors += 1
        end
      rescue => e
        puts "  [blob #{blob.id}] error: #{e.message}"
        errors += 1
      end
    end

    puts "\nDone. #{migrated} migrated, #{skipped} already in place, #{errors} error(s)."
  end

  desc "Move orphaned root-level S3 objects into Images From Chat/ and create MediaAsset records"
  task migrate_orphaned_root_images: :environment do
    require "aws-sdk-s3"

    credentials = Rails.application.credentials
    bucket      = credentials.dig(:digitalocean, :spaces_bucket) || "ig-mcp-images"
    cdn_base    = "https://#{bucket}.sfo3.cdn.digitaloceanspaces.com"
    target_dir  = "Images From Chat"

    client = Aws::S3::Client.new(
      access_key_id:     credentials.dig(:digitalocean, :spaces_access_key_id),
      secret_access_key: credentials.dig(:digitalocean, :spaces_secret_access_key),
      region:            credentials.dig(:digitalocean, :spaces_region) || "sfo3",
      endpoint:          credentials.dig(:digitalocean, :spaces_endpoint) || "https://sfo3.digitaloceanspaces.com",
      force_path_style:  false
    )

    objects = []
    token   = nil
    loop do
      resp = client.list_objects_v2(bucket: bucket, max_keys: 1000, continuation_token: token)
      objects.concat(resp.contents.reject { |o| o.key.include?("/") })
      break unless resp.is_truncated
      token = resp.next_continuation_token
    end

    puts "#{objects.size} root-level object(s) found"

    migrated = 0
    skipped  = 0
    errors   = 0

    objects.each do |obj|
      old_key = obj.key
      new_key = "#{target_dir}/#{old_key}"
      new_url = "#{cdn_base}/#{new_key}"

      if MediaAsset.exists?([ "raw_metadata LIKE ?", "%#{old_key}%" ])
        puts "  #{old_key}: already has a MediaAsset — skipping"
        skipped += 1
        next
      end

      begin
        head   = client.head_object(bucket: bucket, key: old_key)
        mime   = head.content_type.presence || "application/octet-stream"
        size   = head.content_length

        client.copy_object(
          bucket:      bucket,
          copy_source: "#{bucket}/#{old_key}",
          key:         new_key,
          acl:         "public-read",
          content_type: mime,
          metadata_directive: "REPLACE"
        )

        client.delete_object(bucket: bucket, key: old_key)

        media_type = case mime
        when /video/ then :video
        when /audio/ then :audio
        else :image
        end

        MediaAsset.create!(
          external_id:   "chat_#{old_key}",
          external_name: old_key,
          media_type:    media_type,
          status:        :discovered,
          first_seen_at: obj.last_modified,
          file_size:     size,
          mime_type:     mime,
          raw_metadata:  { public_url: new_url, source: "chat_migration", key: new_key }.to_json
        )

        migrated += 1
        puts "  #{old_key} → #{new_key}"
      rescue => e
        puts "  #{old_key}: error — #{e.message}"
        errors += 1
      end
    end

    puts "\nDone. #{migrated} migrated, #{skipped} skipped, #{errors} error(s)."
  end
end
