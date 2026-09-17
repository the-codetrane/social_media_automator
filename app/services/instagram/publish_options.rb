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

    # How Meta reports an untaggable collaborator on POST /{ig-user-id}/media.
    # The top-level message is the unhelpfully generic "Invalid user id"; the
    # subcode is what actually identifies it. Code 110 alone is matched too,
    # because Meta omits the subcode on some responses.
    COLLABORATOR_ERROR_SUBCODE = 2207018
    COLLABORATOR_ERROR_CODE    = 110

    module_function

    # Translate the container error Meta returns for an untaggable collaborator
    # into something the person looking at the failed post can act on.
    #
    # Instagram refuses to tag an account as a collaborator unless the profile
    # is public and the username exists — a private account (very common for a
    # band member's personal handle) is rejected exactly like a typo, with no
    # indication of which of the two it was.
    #
    # @param error [Instagram::Error] raised by the container call
    # @param params [Hash] the params that call was given
    # @return [Instagram::Error] the original error, or a clearer replacement
    def explain_collaborator_error(error, params)
      encoded = params[:collaborators] || params["collaborators"]
      return error if encoded.blank?
      return error unless collaborator_error?(error)

      usernames =
        begin
          Array(JSON.parse(encoded)).join(", ")
        rescue JSON::ParserError
          encoded
        end

      error.class.new(
        "Instagram rejected the collaborator(s) #{usernames}. An account can only be " \
        "tagged as a collaborator if the username exists and the profile is public — " \
        "make it public, or remove it from this post. (#{error.message})",
        code:         error.code,
        subcode:      error.subcode,
        type:         error.type,
        fbtrace_id:   error.fbtrace_id,
        user_message: error.user_message
      )
    end

    def collaborator_error?(error)
      error.subcode.to_i == COLLABORATOR_ERROR_SUBCODE ||
        (error.subcode.blank? && error.code.to_i == COLLABORATOR_ERROR_CODE)
    end

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
      raw = payload["audio_configuration"]
      config = raw.blank? ? {} : (raw.respond_to?(:to_h) ? raw.to_h : raise(ArgumentError, "audio_configuration must be a hash (got #{raw.class})"))
      config = config.stringify_keys

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
