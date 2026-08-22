# frozen_string_literal: true

module Instagram
  # Builds the optional collaboration and audio parameters accepted by
  # POST /{ig-user-id}/media out of a PlannedPost's platform_payload.
  #
  # Both parameters are sent to the Meta API as JSON-encoded strings.
  #
  # Collaborators (feed images, Reels and carousels — NOT stories):
  #   platform_payload["collaborators"] = ["chef_alex", "@bakery_co"]
  #
  # Audio (Reels only) — either nested or flat:
  #   platform_payload["audio_configuration"] = {
  #     "audio_id"     => "587784541076604",  # from Instagram::AudioService
  #     "audio_volume" => 80,                 # optional, 0-100 (default 100)
  #     "video_volume" => 50                  # optional, 0-100 (default 100)
  #   }
  #   # or, for the common "just attach this track" case:
  #   platform_payload["audio_id"] = "587784541076604"
  module PublishOptions
    # POST /{ig-user-id}/media documents a limit of 3 usernames at creation
    # time. (The collaborators edge mentions 5 accounts, but that covers
    # collaborators added in-app after publishing.)
    MAX_COLLABORATORS = 3

    # Valid range for both audio_volume and video_volume.
    VOLUME_RANGE = (0..100)

    module_function

    # @param payload [Hash, nil] a PlannedPost#platform_payload
    # @return [String, nil] JSON array of usernames, or nil when unset
    # @raise [ArgumentError] when more than MAX_COLLABORATORS are given
    def collaborators(payload)
      usernames = normalize_collaborators(payload.to_h["collaborators"])
      return nil if usernames.empty?

      usernames.to_json
    end

    # Clean a raw collaborators value into the usernames Instagram expects:
    # no "@" prefix, no surrounding whitespace, no blanks, no duplicates.
    #
    # Shared with the UI so the edit form validates exactly like the publisher.
    #
    # @param value [Array<String>, String, nil]
    # @return [Array<String>]
    # @raise [ArgumentError] when more than MAX_COLLABORATORS remain
    def normalize_collaborators(value)
      usernames = Array(value)
        .map { |name| name.to_s.strip.delete_prefix("@") }
        .reject(&:blank?)
        .uniq

      if usernames.size > MAX_COLLABORATORS
        raise ArgumentError,
              "Instagram accepts at most #{MAX_COLLABORATORS} collaborators per post " \
              "(#{usernames.size} provided: #{usernames.join(", ")})"
      end

      usernames
    end

    # @param payload [Hash, nil] a PlannedPost#platform_payload
    # @return [String, nil] JSON audio_configuration object, or nil when unset
    # @raise [ArgumentError] when audio_id is missing or a volume is out of range
    def audio_configuration(payload)
      payload = payload.to_h
      config  = payload["audio_configuration"].presence || {}
      config  = config.to_h.stringify_keys

      audio_id = (config["audio_id"] || payload["audio_id"]).presence
      return nil if audio_id.blank?

      result = { "audio_id" => audio_id.to_s }

      %w[audio_volume video_volume].each do |key|
        value = config[key]
        next if value.nil?

        result[key] = coerce_volume(key, value)
      end

      result.to_json
    end

    # @param key [String] "audio_volume" or "video_volume"
    # @return [Integer] a volume within VOLUME_RANGE
    # @raise [ArgumentError] when the value is non-numeric or out of range
    def coerce_volume(key, value)
      volume =
        begin
          Integer(value)
        rescue TypeError, ArgumentError
          raise ArgumentError,
                "#{key} must be an integer between #{VOLUME_RANGE.min} and #{VOLUME_RANGE.max} " \
                "(got #{value.inspect})"
        end

      unless VOLUME_RANGE.cover?(volume)
        raise ArgumentError,
              "#{key} must be between #{VOLUME_RANGE.min} and #{VOLUME_RANGE.max} (got #{volume})"
      end

      volume
    end
  end
end
