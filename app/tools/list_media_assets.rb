require "aws-sdk-s3"

class ListMediaAssets < RubyLLM::Tool
  description "List available media files (images, videos, and audio) across all directories in the " \
              "DigitalOcean Spaces bucket. Use this to discover what media is available before creating posts. " \
              "Returns public CDN URLs ready to pass to resolve_media_asset or sync_media_assets_from_spaces."

  param :prefix,
    type: :string,
    desc: "Optional folder/prefix to filter results, e.g. 'band-photos/' or 'shows/2025/'. Leave blank for all directories.",
    required: false
  param :limit,
    type: :integer,
    desc: "Maximum number of files to return (default: 500, max: 5000)",
    required: false
  param :media_type_filter,
    type: :string,
    desc: "Filter by type: 'image', 'video', 'audio', or leave blank for all",
    required: false

  CDN_BASE   = "https://ig-mcp-images.sfo3.cdn.digitaloceanspaces.com"
  IMAGE_EXTS = %w[.jpg .jpeg .png .gif .webp .heic].freeze
  VIDEO_EXTS = %w[.mp4 .mov .avi .webm .m4v].freeze
  AUDIO_EXTS = %w[.mp3 .wav .m4a .aac .flac].freeze
  MEDIA_EXTS = (IMAGE_EXTS + VIDEO_EXTS + AUDIO_EXTS).freeze

  def execute(prefix: nil, limit: 500, media_type_filter: nil)
    limit = [ [ limit.to_i, 1 ].max, 5000 ].min

    objects = paginate_objects(prefix: prefix.presence, limit: limit)

    media = objects.select { |obj| MEDIA_EXTS.include?(File.extname(obj.key).downcase) }

    if media_type_filter.present?
      media = media.select { |obj| classify(obj.key) == media_type_filter.downcase }
    end

    media.map do |obj|
      {
        url: "#{CDN_BASE}/#{obj.key}",
        key: obj.key,
        directory: directory_of(obj.key),
        media_type: classify(obj.key),
        size_kb: (obj.size / 1024.0).round(1),
        last_modified: obj.last_modified.iso8601
      }
    end
  end

  private

  def paginate_objects(prefix:, limit:)
    objects = []
    continuation_token = nil

    loop do
      remaining = limit - objects.size
      break if remaining <= 0

      response = client.list_objects_v2(
        bucket: bucket,
        prefix: prefix,
        max_keys: [ remaining, 1000 ].min,
        continuation_token: continuation_token
      )

      objects.concat(response.contents)

      break unless response.is_truncated
      continuation_token = response.next_continuation_token
    end

    objects
  end

  def classify(key)
    ext = File.extname(key).downcase
    if IMAGE_EXTS.include?(ext) then "image"
    elsif AUDIO_EXTS.include?(ext) then "audio"
    else "video"
    end
  end

  def directory_of(key)
    dir = File.dirname(key)
    dir == "." ? "(root)" : dir
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
