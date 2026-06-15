# frozen_string_literal: true

module Vision
  module TokenTracker
    def self.record(response)
      return unless response&.input_tokens.present?

      model_record = Model.find_or_create_by!(model_id: Vision::MODEL) do |m|
        m.name     = Vision::MODEL
        m.provider = "anthropic"
      end

      chat = Chat.find_or_create_by!(user_id: nil, model: model_record)

      now = Time.current
      Message.insert({
        role: "assistant",
        content: "",
        chat_id: chat.id,
        model_id: model_record.id,
        input_tokens: response.input_tokens,
        output_tokens: response.output_tokens,
        cached_tokens: response.cache_read_tokens,
        cache_creation_tokens: response.cache_write_tokens,
        created_at: now,
        updated_at: now
      })
    rescue => e
      Rails.logger.error("[Vision::TokenTracker] Failed to record usage: #{e.message}")
    end
  end
end
