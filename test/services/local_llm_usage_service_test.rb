# frozen_string_literal: true

require "test_helper"

class LocalLlmUsageServiceTest < ActiveSupport::TestCase
  setup do
    @chat = chats(:chat_with_messages)
  end

  def record_usage(model:, created_at: Time.current, **tokens)
    @chat.ruby_llm_usages.create!(
      operation: "chat", status: "succeeded", provider: "anthropic", model: model,
      created_at: created_at, **tokens
    )
  end

  test "sums ledger tokens per model and prices them" do
    record_usage(model: "claude-sonnet-4-6", input_tokens: 1_000_000, output_tokens: 0)
    record_usage(model: "claude-sonnet-4-6", input_tokens: 0, output_tokens: 1_000_000,
                 cache_read_tokens: 1_000_000, cache_write_tokens: 1_000_000)

    result = LocalLlmUsageService.new.call
    sonnet = result[:by_model].to_h.fetch("claude-sonnet-4-6")

    assert_equal 1_000_000, sonnet[:total_input]
    assert_equal 1_000_000, sonnet[:total_cache_read]
    assert_in_delta 3.00 + 15.00 + 0.30 + 3.75, sonnet[:cost], 0.0001
  end

  test "ignores usage older than the reporting window" do
    record_usage(model: "claude-sonnet-4-6", input_tokens: 500, created_at: (LocalLlmUsageService::DAYS + 1).days.ago)

    assert_equal 0, LocalLlmUsageService.new.call[:totals][:total_input]
  end
end
