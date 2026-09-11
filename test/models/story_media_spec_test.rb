# frozen_string_literal: true

require "test_helper"

class StoryMediaSpecTest < ActiveSupport::TestCase
  def asset(attrs = {})
    MediaAsset.new({
      external_id:   "spec-#{SecureRandom.hex(4)}",
      media_type:    :video,
      status:        :processed,
      first_seen_at: Time.current,
      width:         1080,
      height:        1920,
      duration_seconds: 15.0,
      file_size:     10 * 1024 * 1024
    }.merge(attrs))
  end

  # -------------------------------------------------------------------------
  # Assets that are fine
  # -------------------------------------------------------------------------

  test "a conforming video passes on both platforms" do
    %w[instagram facebook].each do |platform|
      assert_empty StoryMediaSpec.for(platform).errors_for(asset), platform
    end
  end

  test "the fixture video and image pass on both platforms" do
    %w[instagram facebook].each do |platform|
      spec = StoryMediaSpec.for(platform)
      assert_empty spec.errors_for(media_assets(:sample_video)), platform
      assert_empty spec.errors_for(media_assets(:sample_image)), platform
    end
  end

  test "a platform with no story limits reports nothing" do
    assert_empty StoryMediaSpec.for("tiktok").errors_for(asset(duration_seconds: 600.0))
  end

  test "a nil asset reports nothing" do
    assert_empty StoryMediaSpec.for("instagram").errors_for(nil)
  end

  # -------------------------------------------------------------------------
  # Unknown metadata is not a violation
  # -------------------------------------------------------------------------

  test "missing metadata is passed through rather than rejected on a guess" do
    bare = asset(duration_seconds: nil, width: nil, height: nil, file_size: nil)

    %w[instagram facebook].each do |platform|
      assert_empty StoryMediaSpec.for(platform).errors_for(bare), platform
    end
  end

  test "a video missing only its height skips the resolution check" do
    assert_empty StoryMediaSpec.for("facebook").errors_for(asset(width: 100, height: nil))
  end

  # -------------------------------------------------------------------------
  # Duration
  # -------------------------------------------------------------------------

  test "a video over 60 seconds is rejected on both platforms" do
    %w[instagram facebook].each do |platform|
      errors = StoryMediaSpec.for(platform).errors_for(asset(duration_seconds: 90.0))

      assert_equal 1, errors.size, platform
      assert_match(/90s long/, errors.first)
      assert_match(/3–60 seconds/, errors.first)
    end
  end

  test "a video under 3 seconds is rejected" do
    errors = StoryMediaSpec.for("instagram").errors_for(asset(duration_seconds: 1.5))

    assert_match(/1.5s long/, errors.first)
  end

  test "the boundaries themselves are allowed" do
    spec = StoryMediaSpec.for("facebook")

    assert_empty spec.errors_for(asset(duration_seconds: 3.0))
    assert_empty spec.errors_for(asset(duration_seconds: 60.0))
  end

  test "duration is not checked on an image" do
    assert_empty StoryMediaSpec.for("instagram").errors_for(
      asset(media_type: :image, duration_seconds: 300.0, file_size: 1024)
    )
  end

  # -------------------------------------------------------------------------
  # Resolution — Facebook only
  # -------------------------------------------------------------------------

  test "facebook rejects a video below its minimum frame size" do
    errors = StoryMediaSpec.for("facebook").errors_for(asset(width: 480, height: 854))

    assert_match(/480x854/, errors.first)
    assert_match(/at least 540x960/, errors.first)
  end

  test "instagram does not check frame size" do
    assert_empty StoryMediaSpec.for("instagram").errors_for(asset(width: 480, height: 854))
  end

  test "a landscape video is allowed — Meta letterboxes rather than refusing it" do
    assert_empty StoryMediaSpec.for("facebook").errors_for(asset(width: 1920, height: 1080))
  end

  # -------------------------------------------------------------------------
  # File size
  # -------------------------------------------------------------------------

  test "instagram rejects a video over 100 MB" do
    errors = StoryMediaSpec.for("instagram").errors_for(asset(file_size: 150 * 1024 * 1024))

    assert_match(/150 MB/, errors.first)
    assert_match(/limited to 100 MB/, errors.first)
  end

  test "image limits differ between the platforms" do
    nine_mb = asset(media_type: :image, file_size: 9 * 1024 * 1024, duration_seconds: nil)

    assert_match(/limited to 8 MB/, StoryMediaSpec.for("instagram").errors_for(nine_mb).first)
    assert_empty StoryMediaSpec.for("facebook").errors_for(nine_mb)
  end

  test "several violations are all reported" do
    errors = StoryMediaSpec.for("facebook").errors_for(
      asset(duration_seconds: 120.0, width: 320, height: 240)
    )

    assert_equal 2, errors.size
    assert(errors.any? { |e| e.match?(/seconds/) })
    assert(errors.any? { |e| e.match?(/at least 540x960/) })
  end
end
