# frozen_string_literal: true

module Vision
  class FaceIdentifierService
    def initialize(known_people)
      @known_people = known_people
    end

    # @param target_url [String] public URL of the image to analyze
    # @return [Array<Hash>] e.g. [{"name" => "Mike", "confidence" => "high"}]
    #         or Hash with :error key on failure
    def call(target_url)
      return [] if @known_people.empty?

      ref_urls = @known_people.map(&:public_url)
      labels   = @known_people.each_with_index.map { |p, i| "Image #{i + 1}: #{p.name}" }.join(", ")
      target_label = "Image #{ref_urls.size + 1}"

      prompt = <<~PROMPT
        The first #{ref_urls.size} image(s) are reference photos of known people — #{labels}.
        #{target_label} is the photo to analyze.
        Which people from the reference photos appear in #{target_label}?
        Respond with only a JSON array: [{"name": "...", "confidence": "high|medium|low"}]
        If no one from the references is recognizable, respond with [].
        Do not include any explanation or markdown — raw JSON only.
      PROMPT

      response = nil
      chat = RubyLLM.chat(model: Vision::MODEL)
      chat.before_request { |payload| cache_reference_images(payload, ref_urls.size) }
      response = chat.ask(prompt, with: ref_urls + [ target_url ])

      JSON.parse(response.content.strip.delete_prefix("```json").delete_suffix("```").strip)
    rescue JSON::ParserError
      { error: "Unparseable vision response", raw: response&.content }
    rescue => e
      { error: e.message }
    ensure
      Vision::TokenTracker.record(response) if response
    end

    private

    # Reference photos are identical across every call for a given known_people set, so they're
    # marked as a cached prefix — only the trailing target image is paid for at full price after
    # the first call in a batch (e.g. enrich_media_assets looping over many assets).
    def cache_reference_images(payload, ref_count)
      images = payload[:messages].last[:content].select { |block| block[:type] == "image" }
      images[ref_count - 1][:cache_control] = { type: "ephemeral" }
    end
  end
end
