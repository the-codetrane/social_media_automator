# frozen_string_literal: true

require "test_helper"

# Guards the prompt-caching breakpoints injected in config/initializers/ruby_llm.rb.
#
# These are easy to break silently: the payload still sends fine, the API still answers,
# and the only symptom is the bill. A regression here previously left conversation history
# uncached, which billed ~94% of every request at full input price.
class AnthropicCachePatchTest < ActiveSupport::TestCase
  # Mirrors what RubyLLM's Anthropic provider builds before the patch runs.
  def build_payload(message_count:, tool_count: 3)
    {
      model: "claude-sonnet-4-6",
      system: [ { type: "text", text: "instructions" } ],
      tools: Array.new(tool_count) { |i| { name: "tool_#{i}", description: "d", input_schema: {} } },
      messages: Array.new(message_count) do |i|
        { role: i.even? ? "user" : "assistant", content: [ { type: "text", text: "m#{i}" } ] }
      end
    }
  end

  # A user message carrying tool results, as RubyLLM renders one per :tool record.
  def tool_result_message(id)
    { role: "user", content: [ { type: "tool_result", tool_use_id: id, content: "ok" } ] }
  end

  # Mirrors the order of operations in the patch's #render_payload.
  def apply_patch(payload)
    provider = Object.new
    provider.extend(RubyLLMAnthropicCachePatch)

    payload[:tools]&.last&.merge!(cache_control: { type: "ephemeral" })
    if (last_text = payload[:system]&.reverse&.find { |b| b.is_a?(Hash) && b[:type] == "text" })
      last_text[:cache_control] = { type: "ephemeral" }
    end
    payload[:messages] = provider.send(:coalesce_tool_results, payload[:messages])
    provider.send(:mark_message_breakpoints, payload[:messages])

    payload
  end

  def cached?(message)
    message[:content].last.key?(:cache_control)
  end

  def breakpoint_count(payload)
    payload.to_json.scan("cache_control").size
  end

  test "caches the conversation history, not just tools and system" do
    payload = apply_patch(build_payload(message_count: 11))

    assert cached?(payload[:messages].last), "the newest message must carry a breakpoint"
    assert_operator payload[:messages].count { |m| cached?(m) }, :==, 2,
                    "expected two rolling message breakpoints"
  end

  test "never exceeds Anthropic's four-breakpoint limit" do
    [ 1, 2, 5, 11, 50, 300 ].each do |count|
      payload = apply_patch(build_payload(message_count: count))

      assert_operator breakpoint_count(payload), :<=, 4,
                      "#{count} messages produced #{breakpoint_count(payload)} breakpoints"
    end
  end

  test "places the fallback breakpoint behind the newest one so an expired TTL still hits" do
    payload = apply_patch(build_payload(message_count: 11))
    cached_indexes = payload[:messages].each_index.select { |i| cached?(payload[:messages][i]) }

    assert_equal [ 6, 10 ], cached_indexes,
                 "fallback should trail the newest breakpoint by MESSAGE_CACHE_LOOKBACK"
  end

  test "handles short histories without duplicating a breakpoint" do
    payload = apply_patch(build_payload(message_count: 1))

    assert_equal 1, payload[:messages].count { |m| cached?(m) }
    assert_equal 3, breakpoint_count(payload), "tools + system + one message"
  end

  test "tolerates empty and malformed message content" do
    payload = build_payload(message_count: 2)
    payload[:messages][1][:content] = "a bare string, not blocks"

    assert_nothing_raised { apply_patch(payload) }

    empty = build_payload(message_count: 0)
    assert_nothing_raised { apply_patch(empty) }
  end

  test "still caches the tool and system prefixes" do
    payload = apply_patch(build_payload(message_count: 4))

    assert payload[:tools].last.key?(:cache_control), "last tool definition must be cached"
    assert payload[:system].last.key?(:cache_control), "system block must be cached"
  end

  # ---------------------------------------------------------------------------
  # Parallel tool-result coalescing
  #
  # Anthropic requires every tool_result for one assistant turn in a SINGLE user
  # message. RubyLLM renders one message per result, which is a guaranteed 400.
  # ---------------------------------------------------------------------------

  test "merges parallel tool results into one user message" do
    payload = build_payload(message_count: 0)
    payload[:messages] = [
      { role: "user", content: [ { type: "text", text: "go" } ] },
      { role: "assistant", content: [ { type: "tool_use", id: "a" }, { type: "tool_use", id: "b" } ] },
      tool_result_message("a"),
      tool_result_message("b")
    ]

    messages = apply_patch(payload)[:messages]

    assert_equal 3, messages.size, "the two result messages must collapse into one"
    results = messages[2][:content]
    assert_equal %w[tool_result tool_result], results.map { |b| b[:type] }
    assert_equal %w[a b], results.map { |b| b[:tool_use_id] }, "order must be preserved"
  end

  test "keeps every tool_use id represented after merging" do
    ids = %w[a b c d e]
    payload = build_payload(message_count: 0)
    payload[:messages] = [
      { role: "assistant", content: ids.map { |i| { type: "tool_use", id: i } } }
    ] + ids.map { |i| tool_result_message(i) }

    messages = apply_patch(payload)[:messages]

    assert_equal 2, messages.size
    assert_equal ids, messages[1][:content].map { |b| b[:tool_use_id] }
  end

  test "the merged results stay adjacent to the assistant turn that requested them" do
    payload = build_payload(message_count: 0)
    payload[:messages] = [
      { role: "assistant", content: [ { type: "tool_use", id: "a" } ] },
      tool_result_message("a"),
      tool_result_message("b"),
      { role: "user", content: [ { type: "text", text: "next" } ] }
    ]

    messages = apply_patch(payload)[:messages]
    tool_use_index = messages.index { |m| m[:content].any? { |b| b[:type] == "tool_use" } }
    result_index   = messages.index { |m| m[:content].any? { |b| b[:type] == "tool_result" } }

    assert_equal tool_use_index + 1, result_index
  end

  test "does not merge across separate tool turns" do
    payload = build_payload(message_count: 0)
    payload[:messages] = [
      { role: "assistant", content: [ { type: "tool_use", id: "a" } ] },
      tool_result_message("a"),
      { role: "assistant", content: [ { type: "tool_use", id: "b" } ] },
      tool_result_message("b")
    ]

    messages = apply_patch(payload)[:messages]

    assert_equal 4, messages.size, "an assistant turn between results must break the run"
  end

  test "leaves ordinary user messages and mixed content untouched" do
    payload = build_payload(message_count: 0)
    mixed = { role: "user", content: [ { type: "tool_result", tool_use_id: "a" }, { type: "text", text: "hi" } ] }
    payload[:messages] = [
      { role: "user", content: [ { type: "text", text: "one" } ] },
      { role: "user", content: [ { type: "text", text: "two" } ] },
      mixed,
      tool_result_message("b")
    ]

    messages = apply_patch(payload)[:messages]

    assert_equal 4, messages.size, "only pure tool-result messages may be merged"
  end

  test "coalescing does not mutate the caller's message hashes" do
    first  = tool_result_message("a")
    second = tool_result_message("b")
    payload = build_payload(message_count: 0).merge(messages: [ first, second ])

    apply_patch(payload)

    assert_equal 1, first[:content].size, "the original hash must not be modified in place"
    assert_equal "a", first[:content].first[:tool_use_id]
  end
end
