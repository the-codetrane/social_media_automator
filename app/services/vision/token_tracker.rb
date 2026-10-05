# frozen_string_literal: true

module Vision
  module TokenTracker
    def self.record(response)
      return if response&.tokens.nil? || response.tokens.input.nil?

      model_record = RubyLLM::ActiveRecord::Model.find_or_create_by!(model_id: Vision::MODEL, provider: "anthropic") do |m|
        m.name = Vision::MODEL
      end

      chat = Chat.find_or_create_by!(user_id: nil, ruby_llm_model_id: model_record.id)

      chat.ruby_llm_usages.create!(
        operation: "chat",
        status: "succeeded",
        provider: "anthropic",
        model: Vision::MODEL,
        input_tokens: response.tokens.input,
        output_tokens: response.tokens.output,
        cache_read_tokens: response.tokens.cache_read,
        cache_write_tokens: response.tokens.cache_write
      )
    rescue => e
      Rails.logger.error("[Vision::TokenTracker] Failed to record usage: #{e.message}")
    end
  end
end
