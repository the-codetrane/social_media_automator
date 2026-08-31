# frozen_string_literal: true

module Instagram
  # Fetches the current state of a published Instagram post from the Graph API.
  #
  # Usage:
  #   verifier = Instagram::PostVerifier.new(user)
  #   verifier.verify(external_post_id)["permalink"]
  #   verifier.collaborators(external_post_id)
  #     # => [{ "id" => "178…", "username" => "chef_alex", "invite_status" => "Accepted" }]
  class PostVerifier
    # media_audio_type reports whether a video uses licensed music ("MUSIC")
    # or original audio ("ORIGINAL_SOUND").
    FIELDS = "id,permalink,timestamp,media_type,media_audio_type,like_count,comments_count"

    def initialize(user)
      @client = Instagram::ApiClient.new(user)
    end

    # @param external_post_id [String] the ig_media_id stored on PlannedPost
    # @return [Hash] parsed API response
    def verify(external_post_id)
      @client.get(external_post_id, fields: FIELDS)
    end

    # Co-authors on a published post, with their invite status.
    #
    # Only readable by the account that published the media, and only for feed
    # images, Reels and carousels — Stories are not supported. Accounts that
    # have disabled collaborator tagging are omitted by Meta.
    #
    # @param external_post_id [String] the ig_media_id stored on PlannedPost
    # @return [Array<Hash>] { "id", "username", "invite_status" } per collaborator
    def collaborators(external_post_id)
      response = @client.get("#{external_post_id}/collaborators")
      Array(response["data"])
    end
  end
end
