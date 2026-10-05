class FindSocialTemplate < RubyLLM::Tool
  description "Find available social media caption templates for a given platform"

  parameter :platform,
    type: :string,
    description: "Platform: instagram, youtube, facebook, or tiktok"
  parameter :user_id,
    type: :integer,
    description: "The current user's ID"

  def execute(platform:, user_id:)
    SocialTemplate.for_platform(platform)
                  .where(user_id: [ nil, user_id ])
                  .map do |t|
      {
        id: t.id,
        name: t.name,
        default_caption: t.default_caption,
        max_caption_length: t.max_caption_length,
        recommended_aspect_ratio: t.recommended_aspect_ratio
      }
    end
  end
end
