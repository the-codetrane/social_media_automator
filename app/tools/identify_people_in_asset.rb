class IdentifyPeopleInAsset < RubyLLM::Tool
  description "Identify known people in a media asset image using vision AI. " \
              "Returns recognized band members or other registered subjects. " \
              "Results are cached on the asset; pass force_refresh: true to re-analyze."

  param :asset_id,
    type: :integer,
    desc: "The ID of the MediaAsset image to analyze"

  param :user_id,
    type: :integer,
    desc: "The current user's ID — used to load their registered known people"

  param :force_refresh,
    type: :boolean,
    desc: "Set true to re-run vision analysis even if cached results exist",
    required: false

  def execute(asset_id:, user_id:, force_refresh: false)
    asset = MediaAsset.find_by(id: asset_id)
    return { error: "MediaAsset ##{asset_id} not found" } unless asset
    return { error: "MediaAsset ##{asset_id} has no public URL" } unless asset.public_url?

    if asset.identified_people.present? && !force_refresh
      return { asset_id: asset_id, identified: asset.identified_people, cached: true }
    end

    known_people = KnownPerson.where(user_id: user_id)
    if known_people.empty?
      return { error: "No known people registered for this user. Add reference photos first." }
    end

    result = Vision::FaceIdentifierService.new(known_people).call(asset.public_url)

    if result.is_a?(Array)
      asset.update!(identified_people: result, identified_people_at: Time.current)
      { asset_id: asset_id, identified: result, cached: false }
    else
      result
    end
  end
end
