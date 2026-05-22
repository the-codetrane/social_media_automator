# frozen_string_literal: true

module Vision
  class SimilarityCheckerService
    # @param image_urls [Array<String>] 2–10 public image URLs
    # @return [Array<Hash>] e.g. [{"pair" => [1, 2], "reason" => "..."}]
    #         or Hash with :error key on failure
    def call(image_urls)
      return [] if image_urls.size < 2

      labels = image_urls.each_with_index.map { |_, i| "Image #{i + 1}" }.join(", ")

      prompt = <<~PROMPT
        You are reviewing #{image_urls.size} images for a social media carousel (#{labels}).
        Identify any pairs that are too visually similar to appear together — same subject framing,
        nearly identical composition or angle that would feel repetitive to a viewer scrolling the carousel.
        Respond with only a JSON array: [{"pair": [i, j], "reason": "..."}]
        Use 1-based image numbers. If all images are distinct enough, respond with [].
        Do not include any explanation or markdown — raw JSON only.
      PROMPT

      response = RubyLLM.chat(model: Vision::MODEL)
        .ask(prompt, with: image_urls)

      JSON.parse(response.content.strip.delete_prefix("```json").delete_suffix("```").strip)
    rescue JSON::ParserError
      { error: "Unparseable vision response", raw: response&.content }
    rescue => e
      { error: e.message }
    end
  end
end
