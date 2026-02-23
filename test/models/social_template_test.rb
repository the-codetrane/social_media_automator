# frozen_string_literal: true

require "test_helper"

class SocialTemplateTest < ActiveSupport::TestCase
  # ---------------------------------------------------------------------------
  # Fixtures
  # ---------------------------------------------------------------------------
  test "fixtures are valid" do
    assert social_templates(:instagram_default).valid?
    assert social_templates(:youtube_shorts).valid?
  end

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------
  test "is invalid without a name" do
    template = social_templates(:instagram_default)
    template.name = nil
    assert_not template.valid?
    assert_includes template.errors[:name], "can't be blank"
  end

  test "is invalid without a platform" do
    template = social_templates(:instagram_default)
    template.platform = nil
    assert_not template.valid?
    assert_includes template.errors[:platform], "can't be blank"
  end

  test "enforces uniqueness of name scoped to platform" do
    duplicate = SocialTemplate.new(
      name: social_templates(:instagram_default).name,
      platform: social_templates(:instagram_default).platform
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "allows same name on a different platform" do
    template = SocialTemplate.new(
      name: social_templates(:instagram_default).name,
      platform: :facebook
    )
    assert template.valid?
  end

  test "is invalid with a non-positive max_caption_length" do
    template = social_templates(:instagram_default)
    template.max_caption_length = 0
    assert_not template.valid?
  end

  test "allows nil max_caption_length" do
    template = social_templates(:instagram_default)
    template.max_caption_length = nil
    assert template.valid?
  end

  # ---------------------------------------------------------------------------
  # Enums
  # ---------------------------------------------------------------------------
  test "platform enum has correct values" do
    assert_equal 0, SocialTemplate.platforms[:instagram]
    assert_equal 1, SocialTemplate.platforms[:youtube]
    assert_equal 2, SocialTemplate.platforms[:facebook]
  end

  test "instagram_default is for instagram" do
    assert social_templates(:instagram_default).instagram?
  end

  test "youtube_shorts is for youtube" do
    assert social_templates(:youtube_shorts).youtube?
  end

  # ---------------------------------------------------------------------------
  # Scopes
  # ---------------------------------------------------------------------------
  test ".for_platform returns templates for the given platform" do
    results = SocialTemplate.for_platform(:instagram)
    assert results.all?(&:instagram?)
  end

  test ".global returns templates without a user" do
    results = SocialTemplate.global
    assert results.all? { |t| t.user_id.nil? }
  end

  # ---------------------------------------------------------------------------
  # Associations
  # ---------------------------------------------------------------------------
  test "belongs to user optionally" do
    assert social_templates(:instagram_default).valid?
    assert_nil social_templates(:instagram_default).user_id
  end

  test "has many planned_posts" do
    assert_respond_to social_templates(:instagram_default), :planned_posts
  end
end
