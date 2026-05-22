class CheckCarouselForDuplicates < RubyLLM::Tool
  description "Check a proposed carousel for visually similar images that would feel repetitive. " \
              "Returns flagged pairs with reasons. Run this before finalizing a carousel post."

  param :asset_ids,
    type: :array,
    desc: "Ordered list of MediaAsset IDs for the carousel (2–10 images)"

  def execute(asset_ids:)
    ids = Array(asset_ids).map(&:to_i).reject(&:zero?)
    return { error: "Provide between 2 and 10 asset IDs" } unless ids.size.between?(2, 10)

    assets = MediaAsset.where(id: ids).index_by(&:id)
    missing = ids - assets.keys
    return { error: "Assets not found: #{missing.join(', ')}" } if missing.any?

    image_ids = ids.select { |id| assets[id].image? }
    if image_ids.size < 2
      return { similar_pairs: [], verdict: "No images to compare — carousel contains only videos." }
    end

    urls = image_ids.map do |id|
      asset = assets[id]
      return { error: "MediaAsset ##{id} has no public URL" } unless asset.public_url?
      asset.public_url
    end

    result = Vision::SimilarityCheckerService.new.call(urls)

    if result.is_a?(Array)
      if result.empty?
        { similar_pairs: [], verdict: "All images are visually distinct. Good to go." }
      else
        flagged = result.map do |item|
          pair_indices = Array(item["pair"]).map { |i| i.to_i - 1 }
          { asset_ids: pair_indices.map { |i| image_ids[i] }, reason: item["reason"] }
        end
        { similar_pairs: flagged, verdict: "#{flagged.size} similar pair(s) detected — consider swapping one out." }
      end
    else
      result
    end
  end
end
