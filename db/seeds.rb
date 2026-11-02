# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

puts "🌱 Seeding database..."

# Clear existing data in development
if Rails.env.development?
  puts "Clearing existing data..."
  PlannedPost.destroy_all
  MediaAsset.destroy_all
  SocialTemplate.destroy_all
  Session.destroy_all
  User.destroy_all
end

# =============================================================================
# USERS (10 primary records)
# =============================================================================
puts "Creating users..."

users = []
10.times do |i|
  users << User.create!(
    name: Faker::Name.name,
    email_address: "user#{i + 1}@example.com",
    password: "password123",
    password_confirmation: "password123",
    instagram_user_id: i < 5 ? Faker::Number.number(digits: 15).to_s : nil,
    instagram_access_token: i < 5 ? Faker::Alphanumeric.alphanumeric(number: 100) : nil,
    instagram_token_expires_at: i < 5 ? (Time.current + rand(30..90).days) : nil,
    instagram_page_id: i < 5 ? Faker::Number.number(digits: 15).to_s : nil
  )
end

puts "  Created #{users.count} users"

# =============================================================================
# SESSIONS (5 child records per user)
# =============================================================================
puts "Creating sessions..."

session_count = 0
users.each do |user|
  5.times do
    Session.create!(
      user: user,
      ip_address: Faker::Internet.public_ip_v4_address,
      user_agent: Faker::Internet.user_agent
    )
    session_count += 1
  end
end

puts "  Created #{session_count} sessions"

# =============================================================================
# SOCIAL TEMPLATES (10 primary records)
# =============================================================================
puts "Creating social templates..."

# Create some global templates (no user)
# Name and platform are paired explicitly so a template called "Instagram Feed
# Post" is actually on the instagram platform.
template_specs = [
  [ "Instagram Story Default",  :instagram ],
  [ "Instagram Feed Post",      :instagram ],
  [ "Instagram Reel Template",  :instagram ],
  [ "YouTube Short Format",     :youtube   ],
  [ "YouTube Standard Video",   :youtube   ],
  [ "Facebook Story Template",  :facebook  ],
  [ "Facebook Feed Post",       :facebook  ],
  [ "Instagram Carousel",       :instagram ],
  [ "YouTube Premiere",         :youtube   ],
  [ "Facebook Live Replay",     :facebook  ],
  [ "TikTok Video Default",     :tiktok    ]
]

platforms = [ :instagram, :youtube, :facebook, :tiktok ]
aspect_ratios = [ "1:1", "9:16", "16:9", "4:5", "1.91:1" ]

templates = []
template_specs.each_with_index do |(name, platform), i|
  templates << SocialTemplate.create!(
    name: name,
    platform: platform,
    user: i < 5 ? nil : users.sample, # First 5 are global, rest belong to users
    default_caption: Faker::Lorem.sentence(word_count: rand(5..15)),
    max_caption_length: platform == :tiktok ? 2200 : [ 2200, 5000, 63206 ].sample,
    recommended_aspect_ratio: platform == :tiktok ? "9:16" : aspect_ratios.sample,
    settings: {
      auto_hashtags: [ true, false ].sample,
      schedule_time: [ "morning", "afternoon", "evening", "night" ].sample,
      content_type: [ "promotional", "educational", "entertaining", "inspirational" ].sample
    }
  )
end

puts "  Created #{templates.count} social templates"

# =============================================================================
# MEDIA ASSETS (10 primary records)
# =============================================================================
puts "Creating media assets..."

media_assets = []
external_ids_used = []

10.times do |i|
  # Generate unique external IDs
  external_id = nil
  loop do
    external_id = Faker::Alphanumeric.alphanumeric(number: 44)
    break unless external_ids_used.include?(external_id)
  end
  external_ids_used << external_id

  media_type = [ :image, :video ].sample
  statuses = [ :discovered, :processed, :failed ]

  media_assets << MediaAsset.create!(
    external_id: external_id,
    external_name: media_type == :image ?
      "#{Faker::Lorem.word.downcase}_#{Faker::Number.number(digits: 4)}.#{[ 'jpg', 'png', 'webp' ].sample}" :
      "#{Faker::Lorem.word.downcase}_#{Faker::Number.number(digits: 4)}.#{[ 'mp4', 'mov', 'avi' ].sample}",
    media_type: media_type,
    status: statuses.sample,
    first_seen_at: Time.current - rand(1..365).days,
    last_processed_at: [ nil, Time.current - rand(1..30).days ].sample,
    width: [ 1080, 1920, 3840, 1280, 720 ].sample,
    height: [ 1080, 1920, 2160, 720, 1280 ].sample,
    file_size: rand(100_000..100_000_000),
    duration_seconds: media_type == :video ? rand(1.0..300.0).round(2) : nil,
    mime_type: media_type == :image ?
      [ "image/jpeg", "image/png", "image/webp" ].sample :
      [ "video/mp4", "video/quicktime", "video/x-msvideo" ].sample,
    raw_metadata: {
      source: "upload",
      created_time: Faker::Time.backward(days: 365).iso8601,
      modified_time: Faker::Time.backward(days: 30).iso8601,
      thumbnail_link: Faker::Internet.url
    }
  )
end

puts "  Created #{media_assets.count} media assets"

# =============================================================================
# PLANNED POSTS (5 child records per user)
# =============================================================================
puts "Creating planned posts..."

planned_post_count = 0
processed_assets = media_assets.select { |a| a.status == "processed" }

# If no processed assets, update some to processed for seeding purposes
if processed_assets.empty?
  media_assets.first(5).each { |a| a.update!(status: :processed) }
  processed_assets = media_assets.first(5)
end

users.each do |user|
  5.times do |j|
    platform = platforms.sample

    # TikTok only accepts video, so draw from the video assets for it — and fall
    # back to another platform when this seed run happened to generate none.
    if platform == :tiktok
      asset = processed_assets.select(&:video?).sample
      platform = [ :instagram, :youtube, :facebook ].sample if asset.nil?
    end
    asset ||= processed_assets.sample
    next unless asset
    status = [ :draft, :scheduled, :published, :failed, :canceled ].sample

    # Handle time constraints based on status
    scheduled_at = nil
    published_at = nil

    case status
    when :scheduled
      scheduled_at = Time.current + rand(1..30).days
    when :published
      published_at = Time.current - rand(1..60).days
    when :draft, :failed, :canceled
      # No times needed
    end

    hashtags = Array.new(rand(3..10)) { "##{Faker::Lorem.word.downcase}" }.join(" ")
    caption = "#{Faker::Lorem.paragraph(sentence_count: rand(1..3))} #{hashtags}"

    PlannedPost.create!(
      user: user,
      media_asset: asset,
      social_template: templates.select { |t| t.platform == platform.to_s }.sample,
      platform: platform,
      status: status,
      caption: caption,
      hashtags: hashtags,
      scheduled_at: scheduled_at,
      published_at: published_at,
      external_post_id: status == :published ? Faker::Number.number(digits: 17).to_s : nil,
      platform_payload: {
        original_request: { caption: caption, media_url: Faker::Internet.url },
        response_code: status == :published ? 200 : nil,
        created_at: published_at&.iso8601
      }
    )
    planned_post_count += 1
  end
end

puts "  Created #{planned_post_count} planned posts"

# =============================================================================
# SUMMARY
# =============================================================================
puts ""
puts "=" * 50
puts "🎉 Seeding complete!"
puts "=" * 50
puts "Users:            #{User.count}"
puts "Sessions:         #{Session.count}"
puts "Social Templates: #{SocialTemplate.count}"
puts "Media Assets:     #{MediaAsset.count}"
puts "Planned Posts:    #{PlannedPost.count}"
puts "=" * 50
