require "aws-sdk-s3"

class ListMediaAssets < RubyLLM::Tool
  description "List available media files (images and videos) in the DigitalOcean Spaces bucket. " \
              "Use this to discover what media is available before creating posts. " \
              "Returns public CDN URLs ready to pass to resolve_media_asset."

  param :prefix,
    type: :string,
    desc: "Optional folder/prefix to filter results, e.g. 'band-photos/' or 'shows/'. Leave blank for all files.",
    required: false
  param :limit,
    type: :integer,
    desc: "Maximum number of files to return (default: 50, max: 200)",
    required: false

  CDN_BASE     = "https://ig-mcp-images.sfo3.cdn.digitaloceanspaces.com"
  IMAGE_EXTS   = %w[.jpg .jpeg .png .gif .webp .heic].freeze
  VIDEO_EXTS   = %w[.mp4 .mov .avi .webm .m4v].freeze
  MEDIA_EXTS   = (IMAGE_EXTS + VIDEO_EXTS).freeze

  def execute(prefix: nil, limit: 50)
    limit = [ [ limit.to_i, 1 ].max, 200 ].min

    objects = client.list_objects_v2(
      bucket: bucket,
      prefix: prefix.presence,
      max_keys: limit
    ).contents

    media = objects.select { |obj| MEDIA_EXTS.include?(File.extname(obj.key).downcase) }

    media.map do |obj|
      ext = File.extname(obj.key).downcase
      {
        url: "#{CDN_BASE}/#{obj.key}",
        key: obj.key,
        media_type: IMAGE_EXTS.include?(ext) ? "image" : "video",
        size_kb: (obj.size / 1024.0).round(1),
        last_modified: obj.last_modified.iso8601
      }
    end
  end

  private

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
