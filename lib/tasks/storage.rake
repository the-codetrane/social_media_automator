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
end
