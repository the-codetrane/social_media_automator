class FindSocialTemplate < RubyLLM::Tool
  description "Find available social media caption templates for a given platform"

  param :platform,
    type: :string,
    desc: "Platform: instagram, youtube, or facebook"
  param :user_id,
    type: :integer,
    desc: "The current user's ID"

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
