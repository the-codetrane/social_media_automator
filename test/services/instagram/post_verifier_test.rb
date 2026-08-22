# frozen_string_literal: true

require "test_helper"

module Instagram
  class PostVerifierTest < ActiveSupport::TestCase
    def setup
      @user     = users(:one)
      @verifier = Instagram::PostVerifier.new(@user)
    end

    test "verify calls GET with the media id and expected fields" do
      media_id       = "17846368219941196"
      response_body  = { "id" => media_id, "permalink" => "https://www.instagram.com/p/abc123/", "media_type" => "IMAGE" }
      captured_path  = nil
      captured_params = nil

      mock_client = Object.new
      mock_client.define_singleton_method(:get) do |path, params = {}|
        captured_path   = path
        captured_params = params
        response_body
      end

      @verifier.instance_variable_set(:@client, mock_client)
      result = @verifier.verify(media_id)

      assert_equal media_id, captured_path
      assert_includes captured_params[:fields], "permalink"
      assert_equal "https://www.instagram.com/p/abc123/", result["permalink"]
    end

    test "verify requests media_audio_type so attached music is recorded" do
      captured_params = nil

      mock_client = Object.new
      mock_client.define_singleton_method(:get) do |_path, params = {}|
        captured_params = params
        { "media_audio_type" => "MUSIC" }
      end

      @verifier.instance_variable_set(:@client, mock_client)
      result = @verifier.verify("17846368219941196")

      assert_includes captured_params[:fields], "media_audio_type"
      assert_equal "MUSIC", result["media_audio_type"]
    end

    test "collaborators fetches the collaborators edge and returns the data array" do
      media_id      = "17846368219941196"
      captured_path = nil
      collaborator  = { "id" => "17841400000000009", "username" => "chef_alex", "invite_status" => "Accepted" }

      mock_client = Object.new
      mock_client.define_singleton_method(:get) do |path, _params = {}|
        captured_path = path
        { "data" => [ collaborator ] }
      end

      @verifier.instance_variable_set(:@client, mock_client)
      result = @verifier.collaborators(media_id)

      assert_equal "#{media_id}/collaborators", captured_path
      assert_equal [ collaborator ], result
    end

    test "collaborators returns an empty array when the post has none" do
      mock_client = Object.new
      mock_client.define_singleton_method(:get) { |*_| { "data" => [] } }

      @verifier.instance_variable_set(:@client, mock_client)
      assert_equal [], @verifier.collaborators("17846368219941196")
    end

    test "verify propagates ApiError from the client" do
      mock_client = Object.new
      mock_client.define_singleton_method(:get) { |*_| raise Instagram::ApiError.new("Not found", code: 100) }

      @verifier.instance_variable_set(:@client, mock_client)
      err = assert_raises(Instagram::ApiError) { @verifier.verify("bad_id") }
      assert_equal 100, err.code
    end
  end
end
