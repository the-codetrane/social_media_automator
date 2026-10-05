# frozen_string_literal: true

require "test_helper"

# Guards the request the agent sends to Anthropic.
#
# These break silently: the payload still sends, the API still answers, and the only
# symptom is the bill (uncached history) or a 400 on every parallel tool turn (split
# tool results). The payload is captured from a before_request hook and the call is
# aborted before anything goes over the wire.
class SocialMediaPostAgentTest < ActiveSupport::TestCase
  setup do
    @chat = SocialMediaPostAgent.create!(user: users(:one))
  end

  def captured_payload(llm_chat)
    payload = nil
    llm_chat.before_request do |p|
      payload = p
      throw :captured
    end
    catch(:captured) { llm_chat.complete }
    payload
  end

  def tool_call(id)
    RubyLLM::ToolCall.new(id: id, name: "search_media_assets", arguments: { name: "show" })
  end

  test "enables Anthropic automatic prompt caching" do
    llm_chat = SocialMediaPostAgent.find(@chat.id, user: users(:one)).to_llm
    llm_chat.add_message(role: :user, content: "what's scheduled?")

    payload = captured_payload(llm_chat)

    assert_equal({ type: "ephemeral" }, payload[:cache_control])
    assert_equal "claude-sonnet-5", payload[:model], "new chats should default to Sonnet 5"
    assert payload[:tools].present?, "agent tools should be sent with the request"
  end

  test "sends the per-user instructions as the system prompt" do
    llm_chat = SocialMediaPostAgent.find(@chat.id, user: users(:one)).to_llm
    llm_chat.add_message(role: :user, content: "hi")

    system_text = captured_payload(llm_chat)[:system].map { |b| b[:text] }.join

    assert_includes system_text, "Current user ID: #{users(:one).id}"
    assert_includes system_text, "BRAND VOICE"
  end

  test "sends parallel tool results back in a single user message" do
    llm_chat = SocialMediaPostAgent.find(@chat.id, user: users(:one)).to_llm
    llm_chat.add_message(role: :user, content: "find show photos")
    llm_chat.add_message(role: :assistant, content: "",
                         tool_calls: { "toolu_a" => tool_call("toolu_a"), "toolu_b" => tool_call("toolu_b") })
    llm_chat.add_message(role: :tool, content: "[]", tool_call_id: "toolu_a")
    llm_chat.add_message(role: :tool, content: "[]", tool_call_id: "toolu_b")

    payload = captured_payload(llm_chat)
    result_messages = payload[:messages].select do |m|
      m[:content].is_a?(Array) && m[:content].any? { |b| b[:type] == "tool_result" }
    end

    assert_equal 1, result_messages.size
    assert_equal %w[toolu_a toolu_b], result_messages.first[:content].map { |b| b[:tool_use_id] }
  end
end
