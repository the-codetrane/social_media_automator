# frozen_string_literal: true

require "test_helper"

module Instagram
  class PublishOptionsTest < ActiveSupport::TestCase
    # -------------------------------------------------------------------------
    # .collaborators
    # -------------------------------------------------------------------------

    test "collaborators returns nil when the payload has none" do
      assert_nil Instagram::PublishOptions.collaborators(nil)
      assert_nil Instagram::PublishOptions.collaborators({})
      assert_nil Instagram::PublishOptions.collaborators("collaborators" => [])
      assert_nil Instagram::PublishOptions.collaborators("collaborators" => [ "", "  " ])
    end

    test "collaborators returns a JSON array of usernames" do
      result = Instagram::PublishOptions.collaborators("collaborators" => [ "chef_alex", "bakery_co" ])

      assert_equal [ "chef_alex", "bakery_co" ], JSON.parse(result)
    end

    test "collaborators strips @ prefixes, whitespace and duplicates" do
      result = Instagram::PublishOptions.collaborators(
        "collaborators" => [ "@chef_alex", " chef_alex ", "@bakery_co" ]
      )

      assert_equal [ "chef_alex", "bakery_co" ], JSON.parse(result)
    end

    test "collaborators accepts a single username as a scalar" do
      result = Instagram::PublishOptions.collaborators("collaborators" => "chef_alex")

      assert_equal [ "chef_alex" ], JSON.parse(result)
    end

    test "collaborators raises when more than the documented maximum are given" do
      payload = { "collaborators" => %w[one two three four] }

      error = assert_raises(ArgumentError) { Instagram::PublishOptions.collaborators(payload) }
      assert_match(/at most 3 collaborators/, error.message)
    end

    # -------------------------------------------------------------------------
    # .audio_configuration
    # -------------------------------------------------------------------------

    test "audio_configuration returns nil when no audio is requested" do
      assert_nil Instagram::PublishOptions.audio_configuration(nil)
      assert_nil Instagram::PublishOptions.audio_configuration({})
      assert_nil Instagram::PublishOptions.audio_configuration("audio_configuration" => {})
      assert_nil Instagram::PublishOptions.audio_configuration("audio_id" => "")
    end

    test "audio_configuration accepts a flat audio_id" do
      result = Instagram::PublishOptions.audio_configuration("audio_id" => "587784541076604")

      assert_equal({ "audio_id" => "587784541076604" }, JSON.parse(result))
    end

    test "audio_configuration accepts the nested form with volumes" do
      result = Instagram::PublishOptions.audio_configuration(
        "audio_configuration" => {
          "audio_id"     => "587784541076604",
          "audio_volume" => 80,
          "video_volume" => 50
        }
      )

      assert_equal(
        { "audio_id" => "587784541076604", "audio_volume" => 80, "video_volume" => 50 },
        JSON.parse(result)
      )
    end

    test "audio_configuration coerces string volumes to integers" do
      result = Instagram::PublishOptions.audio_configuration(
        "audio_configuration" => { "audio_id" => "123", "audio_volume" => "0" }
      )

      assert_equal({ "audio_id" => "123", "audio_volume" => 0 }, JSON.parse(result))
    end

    test "audio_configuration omits volumes that were not supplied" do
      result = Instagram::PublishOptions.audio_configuration(
        "audio_configuration" => { "audio_id" => "123", "audio_volume" => 40 }
      )

      parsed = JSON.parse(result)
      assert_equal 40, parsed["audio_volume"]
      assert_not parsed.key?("video_volume")
    end

    test "audio_configuration raises when a volume is out of range" do
      error = assert_raises(ArgumentError) do
        Instagram::PublishOptions.audio_configuration(
          "audio_configuration" => { "audio_id" => "123", "video_volume" => 101 }
        )
      end

      assert_match(/video_volume must be between 0 and 100/, error.message)
    end

    test "audio_configuration raises when a volume is not numeric" do
      error = assert_raises(ArgumentError) do
        Instagram::PublishOptions.audio_configuration(
          "audio_configuration" => { "audio_id" => "123", "audio_volume" => "loud" }
        )
      end

      assert_match(/audio_volume must be an integer between 0 and 100/, error.message)
    end

    # -------------------------------------------------------------------------
    # .explain_collaborator_error
    # -------------------------------------------------------------------------

    test "explain_collaborator_error names the usernames Instagram rejected" do
      original = Instagram::ApiError.new(
        "Invalid user id (Meta error 110/2207018)",
        code: 110, subcode: 2207018, type: "OAuthException", fbtrace_id: "trace1"
      )

      result = Instagram::PublishOptions.explain_collaborator_error(
        original, collaborators: [ "private_handle", "typo_handle" ].to_json
      )

      assert_not_same original, result
      assert_match(/private_handle, typo_handle/, result.message)
      assert_match(/profile is public/, result.message)
      assert_match(/Invalid user id/, result.message)
      assert_equal 110, result.code
      assert_equal 2207018, result.subcode
      assert_equal "trace1", result.fbtrace_id
    end

    test "explain_collaborator_error matches a bare code 110 with no subcode" do
      original = Instagram::ApiError.new("Invalid user id (Meta error 110)", code: 110)

      result = Instagram::PublishOptions.explain_collaborator_error(
        original, collaborators: [ "private_handle" ].to_json
      )

      assert_match(/private_handle/, result.message)
    end

    test "explain_collaborator_error returns the error untouched without collaborators" do
      original = Instagram::ApiError.new("Invalid user id", code: 110, subcode: 2207018)

      result = Instagram::PublishOptions.explain_collaborator_error(original, image_url: "https://example.com/a.png")

      assert_same original, result
    end

    test "explain_collaborator_error returns the error untouched for an unrelated code" do
      original = Instagram::ApiError.new("Media upload failed", code: 2207003)

      result = Instagram::PublishOptions.explain_collaborator_error(
        original, collaborators: [ "someone" ].to_json
      )

      assert_same original, result
    end
  end
end
