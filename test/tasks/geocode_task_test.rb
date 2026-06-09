# frozen_string_literal: true

require "test_helper"

class GeocodeVenueTaskTest < ActiveSupport::TestCase
  GEO_RESULT = Struct.new(:latitude, :longitude, :address, :city, :state, :country).new(
    37.7849, -122.4324, "1805 Geary Blvd, San Francisco, CA 94115", "San Francisco", "California", "United States"
  )

  setup do
    Rails.application.load_tasks
    Rake::Task["geocode:venue"].reenable
  end

  teardown do
    ENV.delete("VENUE")
    ENV.delete("ADDRESS")
    ENV.delete("FORCE")
  end

  # ---------------------------------------------------------------------------
  # Argument validation
  # ---------------------------------------------------------------------------
  test "aborts when VENUE is not set" do
    ENV["ADDRESS"] = "1805 Geary Blvd, San Francisco, CA"
    assert_raises(SystemExit) { Rake::Task["geocode:venue"].invoke }
  end

  test "aborts when ADDRESS is not set" do
    ENV["VENUE"] = "The Fillmore"
    assert_raises(SystemExit) { Rake::Task["geocode:venue"].invoke }
  end

  test "aborts when Geocoder returns no results for the address" do
    ENV["VENUE"]   = "The Fillmore"
    ENV["ADDRESS"] = "Nowhere Land"

    Geocoder.stub(:search, []) do
      assert_raises(SystemExit) { Rake::Task["geocode:venue"].invoke }
    end
  end

  # ---------------------------------------------------------------------------
  # Matching and geocoding
  # ---------------------------------------------------------------------------
  test "sets coordinates on assets whose external_name contains VENUE" do
    asset = MediaAsset.create!(
      external_id: "venue_task_001",
      external_name: "The Fillmore Show.jpg",
      media_type: :image,
      status: :processed,
      first_seen_at: Time.current
    )

    ENV["VENUE"]   = "Fillmore"
    ENV["ADDRESS"] = "1805 Geary Blvd, San Francisco, CA"

    Geocoder.stub(:search, [ GEO_RESULT ]) do
      Rake::Task["geocode:venue"].invoke
    end

    asset.reload
    assert_in_delta 37.7849,    asset.latitude,  0.0001
    assert_in_delta(-122.4324,  asset.longitude, 0.0001)
  end

  test "venue name matching is case-insensitive" do
    asset = MediaAsset.create!(
      external_id: "venue_task_002",
      external_name: "the fillmore grand opening.jpg",
      media_type: :image,
      status: :processed,
      first_seen_at: Time.current
    )

    ENV["VENUE"]   = "FILLMORE"
    ENV["ADDRESS"] = "1805 Geary Blvd, San Francisco, CA"

    Geocoder.stub(:search, [ GEO_RESULT ]) do
      Rake::Task["geocode:venue"].invoke
    end

    asset.reload
    assert_not_nil asset.latitude
  end

  test "does not touch assets that do not mention the venue" do
    other = media_assets(:sample_image)  # external_name: "sunset.jpg"

    ENV["VENUE"]   = "Fillmore"
    ENV["ADDRESS"] = "1805 Geary Blvd, San Francisco, CA"

    Geocoder.stub(:search, [ GEO_RESULT ]) do
      Rake::Task["geocode:venue"].invoke
    end

    other.reload
    assert_nil other.latitude
  end

  # ---------------------------------------------------------------------------
  # FORCE flag
  # ---------------------------------------------------------------------------
  test "skips assets that already have coordinates by default" do
    asset = MediaAsset.create!(
      external_id: "venue_task_003",
      external_name: "The Fillmore Night.jpg",
      media_type: :image,
      status: :processed,
      first_seen_at: Time.current,
      latitude: 1.0,
      longitude: 2.0
    )

    ENV["VENUE"]   = "Fillmore"
    ENV["ADDRESS"] = "1805 Geary Blvd, San Francisco, CA"

    Geocoder.stub(:search, [ GEO_RESULT ]) do
      Rake::Task["geocode:venue"].invoke
    end

    asset.reload
    assert_in_delta 1.0, asset.latitude, 0.0001
  end

  test "overwrites existing coordinates when FORCE=true" do
    asset = MediaAsset.create!(
      external_id: "venue_task_004",
      external_name: "The Fillmore Lights.jpg",
      media_type: :image,
      status: :processed,
      first_seen_at: Time.current,
      latitude: 1.0,
      longitude: 2.0
    )

    ENV["VENUE"]   = "Fillmore"
    ENV["ADDRESS"] = "1805 Geary Blvd, San Francisco, CA"
    ENV["FORCE"]   = "true"

    Geocoder.stub(:search, [ GEO_RESULT ]) do
      Rake::Task["geocode:venue"].invoke
    end

    asset.reload
    assert_in_delta 37.7849, asset.latitude, 0.0001
  end
end
