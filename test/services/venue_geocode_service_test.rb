# frozen_string_literal: true

require "test_helper"

class VenueGeocodeServiceTest < ActiveSupport::TestCase
  GEO_RESULT = Struct.new(:latitude, :longitude, :address, :city, :state, :country).new(
    37.7849, -122.4324, "1805 Geary Blvd, San Francisco, CA 94115", "San Francisco", "California", "United States"
  )

  # ---------------------------------------------------------------------------
  # Geocoder failures
  # ---------------------------------------------------------------------------
  test "returns error result when Geocoder finds no results" do
    Geocoder.stub(:search, []) do
      result = VenueGeocodeService.new(venue: "Nowhere", address: "Nowhere Land").call
      assert_equal 0, result.geocoded
      assert result.errors.any?
      assert_nil result.latitude
    end
  end

  # ---------------------------------------------------------------------------
  # Matching and geocoding
  # ---------------------------------------------------------------------------
  test "sets coordinates on assets whose external_name contains venue" do
    asset = MediaAsset.create!(
      external_id: "svc_test_001", external_name: "The Fillmore Show.jpg",
      media_type: :image, status: :processed, first_seen_at: Time.current
    )

    Geocoder.stub(:search, [ GEO_RESULT ]) do
      VenueGeocodeService.new(venue: "Fillmore", address: "1805 Geary Blvd, San Francisco, CA").call
    end

    asset.reload
    assert_in_delta 37.7849,    asset.latitude,  0.0001
    assert_in_delta(-122.4324,  asset.longitude, 0.0001)
  end

  test "matches URL-encoded venue names in external_name" do
    asset = MediaAsset.create!(
      external_id: "svc_test_url", external_name: "091625-Green%20Room-Web-1.jpg",
      media_type: :image, status: :processed, first_seen_at: Time.current
    )

    Geocoder.stub(:search, [ GEO_RESULT ]) do
      VenueGeocodeService.new(venue: "Green Room", address: "1805 Geary Blvd, San Francisco, CA").call
    end

    asset.reload
    assert_not_nil asset.latitude
  end

  test "matching is case-insensitive" do
    asset = MediaAsset.create!(
      external_id: "svc_test_002", external_name: "the fillmore grand opening.jpg",
      media_type: :image, status: :processed, first_seen_at: Time.current
    )

    Geocoder.stub(:search, [ GEO_RESULT ]) do
      VenueGeocodeService.new(venue: "FILLMORE", address: "1805 Geary Blvd, San Francisco, CA").call
    end

    asset.reload
    assert_not_nil asset.latitude
  end

  test "does not touch assets that do not match the venue" do
    other = media_assets(:sample_image)  # external_name: "sunset.jpg"

    Geocoder.stub(:search, [ GEO_RESULT ]) do
      VenueGeocodeService.new(venue: "Fillmore", address: "1805 Geary Blvd, San Francisco, CA").call
    end

    other.reload
    assert_nil other.latitude
  end

  # ---------------------------------------------------------------------------
  # force flag
  # ---------------------------------------------------------------------------
  test "skips assets that already have coordinates by default" do
    asset = MediaAsset.create!(
      external_id: "svc_test_003", external_name: "The Fillmore Night.jpg",
      media_type: :image, status: :processed, first_seen_at: Time.current,
      latitude: 1.0, longitude: 2.0
    )

    Geocoder.stub(:search, [ GEO_RESULT ]) do
      VenueGeocodeService.new(venue: "Fillmore", address: "1805 Geary Blvd, San Francisco, CA").call
    end

    asset.reload
    assert_in_delta 1.0, asset.latitude, 0.0001
  end

  test "overwrites existing coordinates when force: true" do
    asset = MediaAsset.create!(
      external_id: "svc_test_004", external_name: "The Fillmore Lights.jpg",
      media_type: :image, status: :processed, first_seen_at: Time.current,
      latitude: 1.0, longitude: 2.0
    )

    Geocoder.stub(:search, [ GEO_RESULT ]) do
      VenueGeocodeService.new(venue: "Fillmore", address: "1805 Geary Blvd, San Francisco, CA", force: true).call
    end

    asset.reload
    assert_in_delta 37.7849, asset.latitude, 0.0001
  end

  # ---------------------------------------------------------------------------
  # asset_ids targeting
  # ---------------------------------------------------------------------------
  test "geocodes specific asset_ids even when external_name does not match venue" do
    asset = MediaAsset.create!(
      external_id: "svc_test_id_001", external_name: "some-random-filename.jpg",
      media_type: :image, status: :processed, first_seen_at: Time.current
    )

    Geocoder.stub(:search, [ GEO_RESULT ]) do
      VenueGeocodeService.new(venue: "Fillmore", address: "1805 Geary Blvd, San Francisco, CA",
                              asset_ids: [ asset.id ]).call
    end

    asset.reload
    assert_in_delta 37.7849, asset.latitude, 0.0001
  end

  test "does not touch other assets when asset_ids are specified" do
    target = MediaAsset.create!(
      external_id: "svc_test_id_002", external_name: "The Fillmore Night.jpg",
      media_type: :image, status: :processed, first_seen_at: Time.current
    )
    bystander = MediaAsset.create!(
      external_id: "svc_test_id_003", external_name: "The Fillmore Day.jpg",
      media_type: :image, status: :processed, first_seen_at: Time.current
    )

    Geocoder.stub(:search, [ GEO_RESULT ]) do
      VenueGeocodeService.new(venue: "Fillmore", address: "1805 Geary Blvd, San Francisco, CA",
                              asset_ids: [ target.id ]).call
    end

    target.reload
    bystander.reload
    assert_not_nil target.latitude
    assert_nil bystander.latitude
  end

  # ---------------------------------------------------------------------------
  # Result fields
  # ---------------------------------------------------------------------------
  test "returns geocoded count and resolved coordinates in result" do
    MediaAsset.create!(
      external_id: "svc_test_005", external_name: "Fillmore Event.jpg",
      media_type: :image, status: :processed, first_seen_at: Time.current
    )

    result = Geocoder.stub(:search, [ GEO_RESULT ]) do
      VenueGeocodeService.new(venue: "Fillmore", address: "1805 Geary Blvd, San Francisco, CA").call
    end

    assert_equal 1,        result.geocoded
    assert_equal 0,        result.errors.length
    assert_in_delta 37.7849,   result.latitude,  0.0001
    assert_in_delta(-122.4324, result.longitude, 0.0001)
    assert_equal GEO_RESULT.address, result.resolved_address
  end
end
