# frozen_string_literal: true

require "test_helper"

module Instagram
  class AudioServiceTest < ActiveSupport::TestCase
    def setup
      @user    = users(:one)
      @service = Instagram::AudioService.new(@user)
      @ig_id   = @user.instagram_user_id
    end

    # Replaces the service's ApiClient with a double that records the call.
    def stub_client(response)
      captured = {}

      mock_client = Object.new
      mock_client.define_singleton_method(:get) do |path, params = {}|
        captured[:path]   = path
        captured[:params] = params
        response
      end

      @service.instance_variable_set(:@client, mock_client)
      captured
    end

    # -------------------------------------------------------------------------
    # #search
    # -------------------------------------------------------------------------

    test "search hits ig_audio with audio_type, user_id and search_query" do
      track    = { "audio_id" => "587784541076604", "title" => "Birthday Wish", "audio_type" => "music" }
      captured = stub_client("audio" => [ track ])

      result = @service.search(audio_type: "music", query: "birthday")

      assert_equal "ig_audio", captured[:path]
      assert_equal "music",    captured[:params][:audio_type]
      assert_equal @ig_id,     captured[:params][:user_id]
      assert_equal "birthday", captured[:params][:search_query]
      assert_equal [ track ], result
    end

    test "search omits search_query when blank so trending audio is returned" do
      captured = stub_client("audio" => [])

      @service.search(audio_type: "original_sound")

      assert_equal "original_sound", captured[:params][:audio_type]
      assert_not captured[:params].key?(:search_query)
    end

    test "search defaults to the music catalogue" do
      captured = stub_client("audio" => [])

      @service.search

      assert_equal "music", captured[:params][:audio_type]
    end

    test "search returns an empty array when the response has no audio key" do
      stub_client({})

      assert_equal [], @service.search
    end

    test "search raises on an unknown audio_type" do
      error = assert_raises(ArgumentError) { @service.search(audio_type: "podcast") }

      assert_match(/audio_type must be one of music, original_sound/, error.message)
    end

    test "search raises when the user has no instagram_user_id" do
      @user.instagram_user_id = nil
      stub_client("audio" => [])

      assert_raises(Instagram::ApiError) { @service.search }
    end

    # -------------------------------------------------------------------------
    # #find
    # -------------------------------------------------------------------------

    test "find fetches a single track by id, scoped to the user" do
      track    = { "audio_id" => "587784541076604", "display_artist" => "Shuba" }
      captured = stub_client(track)

      result = @service.find("587784541076604")

      assert_equal "587784541076604", captured[:path]
      assert_equal @ig_id, captured[:params][:user_id]
      assert_equal track, result
    end

    test "find raises when audio_id is blank" do
      assert_raises(ArgumentError) { @service.find(nil) }
      assert_raises(ArgumentError) { @service.find("") }
    end

    test "find propagates ApiError from the client" do
      mock_client = Object.new
      mock_client.define_singleton_method(:get) { |*_| raise Instagram::ApiError.new("Unknown audio", code: 100) }
      @service.instance_variable_set(:@client, mock_client)

      error = assert_raises(Instagram::ApiError) { @service.find("nope") }
      assert_equal 100, error.code
    end
  end
end
