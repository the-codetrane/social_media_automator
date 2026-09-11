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
    # media_product_type is what distinguishes a story from a feed post: a
    # story's media_type reports IMAGE/VIDEO like any other media, while
    # media_product_type is one of AD, FEED, STORY or REELS.
    FIELDS = "id,permalink,timestamp,media_type,media_product_type,media_audio_type,like_count,comments_count"

    # Stories carry no engagement counters and no audio type, and asking for a
    # field a media object does not support is an error (code 100) rather than a
    # null — so they get their own, smaller list.
    STORY_FIELDS = "id,permalink,timestamp,media_type,media_product_type"

    def initialize(user)
      @client = Instagram::ApiClient.new(user)
    end

    # @param external_post_id [String] the ig_media_id stored on PlannedPost
    # @param story [Boolean] read the story-safe field list instead
    # @return [Hash] parsed API response
    def verify(external_post_id, story: false)
      @client.get(external_post_id, fields: story ? STORY_FIELDS : FIELDS)
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
