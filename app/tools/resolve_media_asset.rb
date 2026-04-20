class ResolveMediaAsset < RubyLLM::Tool
  description "Resolve or create a media asset from a public URL. Returns the asset ID required to create a post."

  param :url,
    type: :string,
    desc: "The public HTTP/HTTPS URL of the image or video"

  def execute(url:)
    service = Api::MediaAssetFromUrlService.new(url: url)
    service.call

    if service.success?
      asset = service.media_asset
      { id: asset.id, media_type: asset.media_type, status: asset.status }
    else
      { error: service.error }
    end
  end
end
