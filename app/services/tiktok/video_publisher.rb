# frozen_string_literal: true

require "open-uri"
require "tempfile"

module TikTok
  # Publishes a single video to TikTok via the Content Posting API using
  # DIRECT_POST + FILE_UPLOAD.
  #
  # The flow is:
  #   1. GET the creator's capabilities  → privacy options, duration cap,
  #      account-level comment/duet/stitch restrictions
  #   2. Download the asset from its public URL to a local temp file
  #   3. POST /v2/post/publish/video/init/ with post_info + source_info
  #      → returns publish_id and a signed upload_url
  #   4. PUT the file to upload_url in sequential 5–64 MB chunks
  #   5. Poll /v2/post/publish/status/fetch/ until PUBLISH_COMPLETE
  #
  # FILE_UPLOAD is used rather than PULL_FROM_URL because the latter requires
  # verifying ownership of the media host (DigitalOcean Spaces) with TikTok.
  #
  # Optional platform_payload keys:
  #   "privacy_level"            – one of the creator's privacy_level_options
  #                                (default: PUBLIC_TO_EVERYONE)
  #   "disable_comment"          – true to switch off comments
  #   "disable_duet"             – true to prevent Duets
  #   "disable_stitch"           – true to prevent Stitches
  #   "video_cover_timestamp_ms" – frame to use as the cover image
  #   "brand_content_toggle"     – true for paid partnership disclosure
  #   "brand_organic_toggle"     – true when promoting the creator's own business
  #   "is_aigc"                  – true for AI-generated content
  #
  # Usage:
  #   publisher  = TikTok::VideoPublisher.new(user)
  #   publish_id = publisher.publish(planned_post)
  class VideoPublisher
    INIT_ENDPOINT   = "post/publish/video/init/"
    STATUS_ENDPOINT = "post/publish/status/fetch/"

    # How long to wait between status polling attempts.
    POLL_INTERVAL_SECONDS = 5
    # Total seconds before declaring a publish stuck.  TikTok quotes >2 minutes
    # of processing for a 4 GB upload, before moderation.
    POLL_TIMEOUT_SECONDS  = 600

    # TikTok's chunking rules: every chunk is 5–64 MB except the last, which
    # absorbs the remainder and may reach 128 MB.  A transfer is capped at
    # 1000 chunks.
    MIN_CHUNK_SIZE  = 5 * 1024 * 1024
    MAX_CHUNK_SIZE  = 64 * 1024 * 1024
    MAX_CHUNK_COUNT = 1000

    DEFAULT_PRIVACY_LEVEL = "PUBLIC_TO_EVERYONE"
    DEFAULT_CONTENT_TYPE  = "video/mp4"
    # TikTok counts the title in UTF-16 runes; 2200 is the documented ceiling.
    MAX_TITLE_LENGTH      = 2200

    # Terminal states returned by the status endpoint.
    SUCCESS_STATUSES = %w[PUBLISH_COMPLETE SEND_TO_USER_INBOX].freeze
    FAILED_STATUS    = "FAILED"

    # Boolean post_info flags forwarded straight from platform_payload.
    OPTIONAL_FLAGS = %w[
      brand_content_toggle
      brand_organic_toggle
      is_aigc
    ].freeze

    # @param user [User] must have TikTok OAuth credentials stored
    def initialize(user)
      @user   = user
      @client = TikTok::ApiClient.new(user)
    end

    # Publish the planned post's video to TikTok.
    #
    # @param planned_post [PlannedPost]
    # @return [String] the TikTok publish_id
    # @raise [ArgumentError]              when the asset is not a video
    # @raise [TikTok::PermanentError]     on unrecoverable configuration errors
    # @raise [TikTok::RateLimitError]     when the posting quota is exhausted
    # @raise [TikTok::PublishTimeoutError] when processing does not finish in time
    def publish(planned_post)
      asset   = planned_post.media_asset
      payload = planned_post.platform_payload.to_h

      validate_video_asset!(asset)

      creator = TikTok::CreatorInfoService.new(@user).query
      privacy = resolve_privacy_level(payload, creator)
      validate_duration!(asset, creator)

      tempfile = download(asset)
      size     = tempfile.size
      plan     = chunk_plan(size)

      init       = initialize_upload(planned_post, payload, creator, privacy, size, plan)
      publish_id = init["publish_id"].presence ||
        raise(TikTok::ApiError, "TikTok returned no publish_id: #{init.inspect}")
      upload_url = init["upload_url"].presence ||
        raise(TikTok::ApiError, "TikTok returned no upload_url: #{init.inspect}")

      upload_chunks!(tempfile, upload_url, asset, size, plan)
      status = wait_until_published!(publish_id)

      planned_post.update!(
        status:           :published,
        external_post_id: publish_id,
        published_at:     Time.current,
        platform_payload: payload.merge(
          "tiktok_publish_id" => publish_id,
          "tiktok_post_id"    => public_post_id(status),
          "privacy_level"     => privacy,
          "publish_status"    => status["status"]
        ).compact
      )

      publish_id
    rescue TikTok::Error => e
      planned_post.mark_failed!(e.message)
      raise
    ensure
      tempfile&.close
      tempfile&.unlink
    end

    private

    # ------------------------------------------------------------------
    # Validation
    # ------------------------------------------------------------------

    # PlannedPost validates this too, but a post created before that validation
    # existed — or one whose asset was swapped — can still reach here.  It is a
    # PermanentError rather than an ArgumentError so the publish job marks the
    # post failed instead of letting the job crash with nothing recorded.
    def validate_video_asset!(asset)
      unless asset.video?
        raise TikTok::PermanentError,
              "TikTok::VideoPublisher requires a video MediaAsset " \
              "(got media_type=#{asset.media_type} for MediaAsset##{asset.id})"
      end

      unless asset.public_url?
        raise TikTok::PermanentError,
              "MediaAsset #{asset.id} has no public URL. " \
              "Attach a file via ActiveStorage or set raw_metadata[\"public_url\"]."
      end
    end

    # TikTok rejects the init call outright when the video is longer than the
    # creator is allowed to post, so check locally where we can.
    def validate_duration!(asset, creator)
      max = creator["max_video_post_duration_sec"].to_i
      return unless max.positive?
      return if asset.duration_seconds.blank?
      return if asset.duration_seconds <= max

      raise TikTok::PermanentError,
            "MediaAsset #{asset.id} is #{asset.duration_seconds.round}s long but this " \
            "creator can only post videos up to #{max}s."
    end

    # The submitted privacy_level must be one of the creator's own options.
    def resolve_privacy_level(payload, creator)
      requested = payload["privacy_level"].presence || DEFAULT_PRIVACY_LEVEL
      options   = Array(creator["privacy_level_options"])

      return requested if options.empty? || options.include?(requested)

      raise TikTok::PermanentError,
            "Privacy level '#{requested}' is not available for this creator. " \
            "Available options: #{options.join(', ')}."
    end

    # ------------------------------------------------------------------
    # Chunking
    # ------------------------------------------------------------------

    # Work out the chunk_size / total_chunk_count pair TikTok expects.
    #
    # Files under the 5 MB minimum go up as a single whole-file chunk; anything
    # larger is split into floor(size / chunk_size) chunks, with the final one
    # absorbing the remainder.
    #
    # @param size [Integer] file size in bytes
    # @return [Hash] { chunk_size:, total_chunk_count: }
    def chunk_plan(size)
      raise TikTok::UploadError, "Video file is empty" if size.to_i <= 0

      return { chunk_size: size, total_chunk_count: 1 } if size <= MIN_CHUNK_SIZE

      chunk_size = [ size, MAX_CHUNK_SIZE ].min
      total      = size / chunk_size

      if total > MAX_CHUNK_COUNT
        raise TikTok::UploadError,
              "Video is too large to upload: #{size} bytes needs #{total} chunks " \
              "(TikTok allows at most #{MAX_CHUNK_COUNT})."
      end

      { chunk_size: chunk_size, total_chunk_count: total }
    end

    # ------------------------------------------------------------------
    # TikTok API calls
    # ------------------------------------------------------------------

    def initialize_upload(planned_post, payload, creator, privacy, size, plan)
      body = {
        post_info:   build_post_info(planned_post, payload, creator, privacy),
        source_info: {
          source:            "FILE_UPLOAD",
          video_size:        size,
          chunk_size:        plan[:chunk_size],
          total_chunk_count: plan[:total_chunk_count]
        }
      }

      Rails.logger.debug(
        "[TikTok::VideoPublisher] Initialising upload for PlannedPost##{planned_post.id} " \
        "(#{size} bytes in #{plan[:total_chunk_count]} chunk(s))"
      )

      result = @client.post(INIT_ENDPOINT, body)
      result["data"] || {}
    end

    def build_post_info(planned_post, payload, creator, privacy)
      info = {
        title:           build_title(planned_post),
        privacy_level:   privacy,
        # An account-level restriction wins over anything in platform_payload:
        # TikTok rejects the post if we ask to allow what the creator disallows.
        disable_comment: flag(payload, "disable_comment", forced_by: creator["comment_disabled"]),
        disable_duet:    flag(payload, "disable_duet",    forced_by: creator["duet_disabled"]),
        disable_stitch:  flag(payload, "disable_stitch",  forced_by: creator["stitch_disabled"])
      }

      if payload["video_cover_timestamp_ms"].present?
        info[:video_cover_timestamp_ms] = payload["video_cover_timestamp_ms"].to_i
      end

      OPTIONAL_FLAGS.each do |key|
        info[key.to_sym] = true if payload[key]
      end

      info
    end

    def flag(payload, key, forced_by:)
      return true if forced_by
      payload[key] ? true : false
    end

    def upload_chunks!(tempfile, upload_url, asset, size, plan)
      chunk_size   = plan[:chunk_size]
      total        = plan[:total_chunk_count]
      content_type = asset.mime_type.presence || DEFAULT_CONTENT_TYPE

      tempfile.rewind

      total.times do |index|
        first_byte = index * chunk_size
        last_byte  = index == total - 1 ? size - 1 : first_byte + chunk_size - 1
        length     = last_byte - first_byte + 1

        bytes = tempfile.read(length)
        raise TikTok::UploadError, "Unexpected end of file at byte #{first_byte}" if bytes.nil?

        Rails.logger.debug(
          "[TikTok::VideoPublisher] Uploading chunk #{index + 1}/#{total} " \
          "(bytes #{first_byte}-#{last_byte}/#{size})"
        )

        @client.upload_chunk(
          upload_url, bytes,
          content_type: content_type,
          first_byte:   first_byte,
          last_byte:    last_byte,
          total_bytes:  size
        )
      end
    end

    # Poll POST /post/publish/status/fetch/ until the publish reaches a
    # terminal state or the timeout elapses.
    #
    # @return [Hash] the final status payload
    def wait_until_published!(publish_id, timeout: POLL_TIMEOUT_SECONDS)
      deadline = Time.current + timeout.seconds

      loop do
        result = @client.post(STATUS_ENDPOINT, publish_id: publish_id)
        data   = result["data"] || {}
        status = data["status"]

        if SUCCESS_STATUSES.include?(status)
          Rails.logger.debug("[TikTok::VideoPublisher] Publish #{publish_id} reached #{status}.")
          return data
        end

        if status == FAILED_STATUS
          raise TikTok::ApiError,
                "TikTok publish #{publish_id} failed: #{data['fail_reason'] || 'unknown reason'}"
        end

        Rails.logger.debug(
          "[TikTok::VideoPublisher] Publish #{publish_id} status: #{status}. " \
          "Retrying in #{POLL_INTERVAL_SECONDS}s…"
        )

        if Time.current >= deadline
          raise TikTok::PublishTimeoutError,
                "TikTok publish #{publish_id} did not complete within #{timeout}s (last status: #{status})"
        end

        sleep POLL_INTERVAL_SECONDS
      end
    end

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    # NOTE: "publicaly_available_post_id" is TikTok's own spelling — do not
    # "fix" it.  It is a list, and only appears once moderation has approved a
    # publicly visible post, which can lag PUBLISH_COMPLETE by hours.
    def public_post_id(status)
      Array(status["publicaly_available_post_id"]).first
    end

    def build_title(planned_post)
      parts = [ planned_post.caption, planned_post.hashtags ].compact.reject(&:empty?)
      parts.join("\n\n").truncate(MAX_TITLE_LENGTH, omission: "…")
    end

    def download(asset)
      ext = asset.file.attached? ? File.extname(asset.file.filename.to_s) : ""
      ext = ".mp4" if ext.blank?

      tempfile = Tempfile.new([ "tiktok_upload", ext ], binmode: true)

      Rails.logger.debug("[TikTok::VideoPublisher] Downloading MediaAsset##{asset.id} from #{asset.public_url}")
      URI.open(asset.public_url, "rb") { |src| IO.copy_stream(src, tempfile) }
      tempfile.rewind

      tempfile
    end
  end
end
