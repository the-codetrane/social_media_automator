require "aws-sdk-s3"
require "digest"

class SyncMediaAssetsFromSpaces < RubyLLM::Tool
  description "Scan DigitalOcean Spaces and upsert MediaAsset records for every media file found. " \
              "Use this to build or refresh the full inventory of available media in the database. " \
              "Run once before bulk-creating posts so all assets are already registered. " \
              "Returns a summary of how many records were created, skipped, or failed."

  param :prefix,
    type: :string,
    desc: "Optional folder prefix to limit the sync, e.g. 'concerts/2025/'. Leave blank to sync all directories.",
    required: false
  param :dry_run,
    type: :boolean,
    desc: "If true, reports what would be created without writing to the database (default: false).",
    required: false

  CDN_BASE   = "https://ig-mcp-images.sfo3.cdn.digitaloceanspaces.com"
  IMAGE_EXTS = %w[.jpg .jpeg .png .gif .webp .heic].freeze
  VIDEO_EXTS = %w[.mp4 .mov .avi .webm .m4v].freeze
  AUDIO_EXTS = %w[.mp3 .wav .m4a .aac .flac].freeze
  MEDIA_EXTS = (IMAGE_EXTS + VIDEO_EXTS + AUDIO_EXTS).freeze

  def execute(prefix: nil, dry_run: false)
    objects = paginate_objects(prefix: prefix.presence)
    media_objects = objects.select { |obj| MEDIA_EXTS.include?(File.extname(obj.key).downcase) }

    created = 0
    skipped = 0
    failed  = 0
    errors  = []

    media_objects.each do |obj|
      url         = "#{CDN_BASE}/#{obj.key}"
      external_id = generate_external_id(url)

      if MediaAsset.exists?(external_id: external_id)
        skipped += 1
        next
      end

      if dry_run
        created += 1
        next
      end

      begin
        MediaAsset.create!(
          external_id:   external_id,
          external_name: File.basename(obj.key),
          media_type:    classify(obj.key),
          status:        :discovered,
          first_seen_at: obj.last_modified || Time.current,
          raw_metadata:  { public_url: url, source: "spaces_sync", key: obj.key }.to_json
        )
        created += 1
      rescue => e
        failed += 1
        errors << "#{obj.key}: #{e.message}"
      end
    end

    result = {
      total_scanned: media_objects.size,
      created: created,
      skipped: skipped,
      dry_run: dry_run
    }
    result[:failed]  = failed  if failed > 0
    result[:errors]  = errors  if errors.any?
    result
  end

  private

  def paginate_objects(prefix:)
    objects = []
    continuation_token = nil

    loop do
      response = client.list_objects_v2(
        bucket: bucket,
        prefix: prefix,
        max_keys: 1000,
        continuation_token: continuation_token
      )

      objects.concat(response.contents)

      break unless response.is_truncated
      continuation_token = response.next_continuation_token
    end

    objects
  end

  def generate_external_id(url)
    "api_#{Digest::SHA256.hexdigest(url)[0, 16]}"
  end

  def classify(key)
    ext = File.extname(key).downcase
    if IMAGE_EXTS.include?(ext) then :image
    elsif AUDIO_EXTS.include?(ext) then :audio
    else :video
    end
  end

  def client
    @client ||= Aws::S3::Client.new(
      access_key_id:     credentials.dig(:digitalocean, :spaces_access_key_id),
      secret_access_key: credentials.dig(:digitalocean, :spaces_secret_access_key),
      region:            credentials.dig(:digitalocean, :spaces_region) || "sfo3",
      endpoint:          credentials.dig(:digitalocean, :spaces_endpoint) || "https://sfo3.digitaloceanspaces.com",
      force_path_style:  false
    )
  end

  def bucket
    credentials.dig(:digitalocean, :spaces_bucket) || "ig-mcp-images"
  end

  def credentials
    Rails.application.credentials
  end
end
