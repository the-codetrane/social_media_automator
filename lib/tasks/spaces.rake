# frozen_string_literal: true

namespace :spaces do
  desc "List files in DigitalOcean Spaces bucket"
  task list: :environment do
    service = ActiveStorage::Blob.services.fetch(:digitalocean)
    bucket = service.bucket
    prefix = ENV.fetch("PREFIX", nil)
    limit = ENV.fetch("LIMIT", 100).to_i

    puts "Bucket: #{bucket.name}"
    puts "Prefix: #{prefix || '(root)'}"
    puts "-" * 60

    objects = prefix ? bucket.objects(prefix: prefix) : bucket.objects
    count = 0

    objects.limit(limit).each do |obj|
      size_kb = (obj.size / 1024.0).round(2)
      puts "#{obj.key.ljust(50)} #{size_kb} KB"
      count += 1
    end

    puts "-" * 60
    puts "Total: #{count} files (limited to #{limit})"
  end

  desc "List directories (common prefixes) in DigitalOcean Spaces"
  task dirs: :environment do
    service = ActiveStorage::Blob.services.fetch(:digitalocean)
    client = service.client
    bucket_name = service.bucket.name

    resp = client.list_objects_v2(bucket: bucket_name, delimiter: "/")

    puts "Directories in #{bucket_name}:"
    resp.common_prefixes.each do |prefix|
      puts "  📁 #{prefix.prefix}"
    end

    puts "\nRoot files:"
    resp.contents.each do |obj|
      puts "  📄 #{obj.key}"
    end
  end

  desc "Show bucket info and test connection"
  task info: :environment do
    service = ActiveStorage::Blob.services.fetch(:digitalocean)
    bucket = service.bucket

    puts "=== DigitalOcean Spaces Connection Test ==="
    puts "Bucket: #{bucket.name}"
    puts "Region: #{service.client.config.region}"
    puts "Endpoint: #{service.client.config.endpoint}"

    # Test by counting objects
    count = bucket.objects.limit(1000).count
    puts "Objects (up to 1000): #{count}"
    puts "✓ Connection successful!"
  rescue => e
    puts "✗ Connection failed: #{e.message}"
  end

  desc "Allow browser direct uploads to the bucket (ORIGINS=https://a.example,https://b.example)"
  task cors: :environment do
    service = ActiveStorage::Blob.services.fetch(:digitalocean)
    origins = ENV.fetch("ORIGINS", "https://socialmediaautomator.cainandco.band").split(",").map(&:strip)

    service.client.put_bucket_cors(
      bucket: service.bucket.name,
      cors_configuration: {
        cors_rules: [ {
          allowed_origins: origins,
          allowed_methods: %w[PUT],
          allowed_headers: %w[*],
          max_age_seconds: 3600
        } ]
      }
    )

    puts "CORS rule set on #{service.bucket.name} for #{origins.join(", ")}"
  end
end
