# frozen_string_literal: true

# Meta's published limits for story media, and the check that a MediaAsset
# meets them.
#
# Only hard failures are encoded here — the limits Meta rejects outright. Aspect
# ratio is deliberately absent: both platforms document 9:16, but in practice
# they letterbox or crop anything else rather than refusing it, so enforcing it
# would block work Meta would have accepted.
#
# Every limit is skipped when the MediaAsset has not recorded the value it needs
# (width, height, duration and file size are all nullable), so an asset with
# thin metadata is passed through to Meta rather than rejected on a guess.
#
#   StoryMediaSpec.for("facebook").errors_for(asset)
#     # => ["is 1.5 minutes long — Facebook stories accept 3–60 seconds"]
class StoryMediaSpec
  # duration is seconds; sizes are bytes; min_width/min_height are pixels.
  #
  # Instagram: JPEG images to 8 MB, video 3–60 s to 100 MB.
  # Facebook:  images to 10 MB, video 3–60 s at 540x960 or better. Meta's spec
  #   table says 3–90 s and its limitations section then caps video stories at
  #   60 s, so the lower of the two is used.
  LIMITS = {
    "instagram" => {
      min_duration:    3,
      max_duration:    60,
      max_image_bytes: 8 * 1024 * 1024,
      max_video_bytes: 100 * 1024 * 1024
    },
    "facebook" => {
      min_duration:    3,
      max_duration:    60,
      max_image_bytes: 10 * 1024 * 1024,
      min_width:       540,
      min_height:      960
    }
  }.freeze

  # @param platform [String, Symbol]
  # @return [StoryMediaSpec] a spec with no limits when the platform has none
  def self.for(platform)
    new(platform, LIMITS.fetch(platform.to_s, {}))
  end

  def initialize(platform, limits)
    @platform = platform.to_s
    @limits   = limits
  end

  # @param media_asset [MediaAsset]
  # @return [Array<String>] one message per violated limit, empty when fine
  def errors_for(media_asset)
    return [] if media_asset.blank? || @limits.empty?

    if media_asset.video?
      [ duration_error(media_asset), resolution_error(media_asset), video_size_error(media_asset) ].compact
    else
      [ image_size_error(media_asset) ].compact
    end
  end

  private

  def platform_name
    @platform.capitalize
  end

  def duration_error(asset)
    duration = asset.duration_seconds
    return nil if duration.blank?
    return nil if duration >= @limits[:min_duration] && duration <= @limits[:max_duration]

    "is #{format('%g', duration.round(1))}s long — #{platform_name} stories accept " \
      "#{@limits[:min_duration]}–#{@limits[:max_duration]} seconds"
  end

  # Meta answers an undersized video with "Resolution too low" during the
  # processing phase, minutes after the upload has already been paid for.
  def resolution_error(asset)
    min_width  = @limits[:min_width]
    min_height = @limits[:min_height]
    return nil if min_width.blank? || asset.width.blank? || asset.height.blank?
    return nil if asset.width >= min_width && asset.height >= min_height

    "is #{asset.width}x#{asset.height} — #{platform_name} stories need at least #{min_width}x#{min_height}"
  end

  def video_size_error(asset)
    size_error(asset, @limits[:max_video_bytes], "video")
  end

  def image_size_error(asset)
    size_error(asset, @limits[:max_image_bytes], "image")
  end

  def size_error(asset, max_bytes, kind)
    return nil if max_bytes.blank? || asset.file_size.blank?
    return nil if asset.file_size <= max_bytes

    "is #{megabytes(asset.file_size)} — #{platform_name} story #{kind}s are limited to #{megabytes(max_bytes)}"
  end

  def megabytes(bytes)
    "#{format('%g', (bytes.to_f / (1024 * 1024)).round(1))} MB"
  end
end
