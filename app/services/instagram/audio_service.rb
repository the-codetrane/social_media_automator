# frozen_string_literal: true

module Instagram
  # Searches Instagram's audio catalogue so a track can be attached to a Reel
  # at publish time (Instagram Audio API, Graph API v26.0+).
  #
  # Two catalogues are available:
  #   "music"           – royalty-free tracks from Meta's Sound Collection
  #   "original_sound"  – original audio lifted from other Reels
  #
  # Usage:
  #   service = Instagram::AudioService.new(user)
  #   tracks  = service.search(audio_type: "music", query: "lofi")
  #   track   = service.find(tracks.first["audio_id"])
  #
  #   planned_post.platform_payload["audio_id"] = track["audio_id"]
  #
  # Notes / limitations from the Meta docs:
  #   - Only audio licensed for third-party use is returned, so the catalogue
  #     is narrower than what the native Instagram app offers.
  #   - Omitting +query+ returns trending audio.
  #   - +download_url+ is a temporary preview link (~1.5 days).
  #   - There is no way to preview a Reel with its attached audio before
  #     publishing.
  #   - Requires Instagram API with Facebook Login (which is what we use) plus
  #     the instagram_basic and instagram_content_publish permissions.
  class AudioService
    # GET edge for both searching and (with an ID) fetching a single track.
    SEARCH_PATH = "ig_audio"

    # Accepted values for the required audio_type parameter.
    AUDIO_TYPES = %w[music original_sound].freeze

    # Fields present on an audio object. Music and original sounds each
    # populate a different subset.
    AUDIO_FIELDS = %w[
      audio_id
      title
      audio_type
      duration_in_ms
      display_artist
      cover_artwork_thumbnail_uri
      download_url
      on_platform_audio_preview_link
      ig_username
      profile_picture_url
      is_ads_eligible
    ].freeze

    # @param user [User] must have instagram_user_id + instagram_access_token set
    def initialize(user)
      @user   = user
      @client = Instagram::ApiClient.new(user)
    end

    # Search the audio catalogue.
    #
    # @param audio_type [String] "music" or "original_sound"
    # @param query [String, nil] keyword filter; trending audio when blank
    # @return [Array<Hash>] audio objects (see AUDIO_FIELDS)
    # @raise [ArgumentError] on an unknown audio_type
    # @raise [Instagram::ApiError] on Meta API errors
    def search(audio_type: "music", query: nil)
      validate_audio_type!(audio_type)

      params = { audio_type: audio_type, user_id: ig_user_id }
      params[:search_query] = query if query.present?

      response = @client.get(SEARCH_PATH, params)
      Array(response["audio"])
    end

    # Fetch a single audio track's metadata.
    #
    # @param audio_id [String]
    # @return [Hash] the audio object (see AUDIO_FIELDS)
    # @raise [Instagram::ApiError] on Meta API errors
    def find(audio_id)
      raise ArgumentError, "audio_id is required" if audio_id.blank?

      @client.get(audio_id.to_s, user_id: ig_user_id)
    end

    private

    def validate_audio_type!(audio_type)
      return if AUDIO_TYPES.include?(audio_type.to_s)

      raise ArgumentError,
            "audio_type must be one of #{AUDIO_TYPES.join(", ")} (got #{audio_type.inspect})"
    end

    def ig_user_id
      @ig_user_id ||= @user.instagram_user_id.presence ||
        raise(Instagram::ApiError, "User #{@user.id} has no instagram_user_id set")
    end
  end
end
