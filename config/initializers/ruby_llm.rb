RubyLLM.configure do |config|
  config.perplexity_api_key = Rails.application.credentials.perplexity_api_key || ENV["PERPLEXITY_API_KEY"]
  config.anthropic_api_key  = if Rails.env.production?
    Rails.application.credentials.anthropic_api_key || ENV["ANTHROPIC_API_KEY"]
  else
    ENV["ANTHROPIC_API_KEY"] || Rails.application.credentials.anthropic_api_key
  end
  config.default_model = "claude-sonnet-4-6"
  config.logger = Rails.logger
end

# Inject Anthropic prompt-caching breakpoints into every API call.
#
# Anthropic caches any prefix whose last block carries cache_control: {type: "ephemeral"}.
# Render order is tools → system → messages, so a breakpoint caches everything before it.
# We mark:
#   1. The last tool definition   — tool schemas don't change between turns.
#   2. The last system block      — the agent instructions are the same for every turn.
#   3. The tail of the message history — the conversation so far, which every later turn resends.
#
# (3) is the one that matters. Tools + system are only ~7K tokens, but a tool-heavy chat resends
# its whole history on every turn, so without a message breakpoint ~94% of each request was billed
# as uncached input at 1.0× — which was 96% of the entire API bill.
#
# A cache write costs 1.25× and a read 0.1×, so a breakpoint pays for itself the first time the
# prefix is reused. Anthropic allows 4 breakpoints; the two below leave the history cached even
# when the newest breakpoint has aged out of the 5-minute TTL.
#
# This patch also repairs how parallel tool results are serialized — see #coalesce_tool_results.
module RubyLLMAnthropicCachePatch
  # How far back the second (fallback) message breakpoint sits from the end of the history.
  MESSAGE_CACHE_LOOKBACK = 4

  private

  def render_payload(messages, tools:, temperature:, model:, stream: false,
                     schema: nil, thinking: nil, tool_prefs: nil)
    payload = super

    payload[:tools]&.last&.merge!(cache_control: { type: "ephemeral" })

    if (last_text = payload[:system]&.reverse&.find { |b| b.is_a?(Hash) && b[:type] == "text" })
      last_text[:cache_control] = { type: "ephemeral" }
    end

    # Must run before the breakpoints are placed: coalescing changes message indices,
    # and a marked message could otherwise be merged away.
    payload[:messages] = coalesce_tool_results(payload[:messages])
    mark_message_breakpoints(payload[:messages])

    payload
  end

  # Merge consecutive tool-result messages into a single user message.
  #
  # When the model makes N parallel tool calls, RubyLLM persists each result as its own
  # :tool message and renders each as its own `{role: "user", content: [tool_result]}`.
  # Anthropic requires every tool_result for one assistant turn to arrive in ONE user
  # message, so the split form is rejected with a 400 on every parallel turn.
  #
  # Merging here — rather than forcing sequential tool calls — keeps parallel tool use
  # working, which is what the model does by default and what keeps round trips (and
  # therefore resent history) down.
  def coalesce_tool_results(messages)
    return messages if messages.blank?

    messages.each_with_object([]) do |message, merged|
      previous = merged.last

      if tool_result_message?(message) && tool_result_message?(previous)
        # dup so the merge never mutates a hash the caller still holds a reference to.
        merged[-1] = previous.merge(content: previous[:content] + message[:content])
      else
        merged << message
      end
    end
  end

  # A message is a pure tool-result carrier only when every block is a tool_result.
  # Anything mixed (text alongside results) is left alone.
  def tool_result_message?(message)
    return false unless message.is_a?(Hash)
    return false unless message[:role].to_s == "user"

    blocks = message[:content]
    blocks.is_a?(Array) && blocks.any? &&
      blocks.all? { |b| b.is_a?(Hash) && b[:type].to_s == "tool_result" }
  end

  # Mark the trailing messages so the accumulated history is served from cache.
  # Content is an array of blocks; cache_control goes on the last block of the message.
  def mark_message_breakpoints(messages)
    return if messages.blank?

    targets = [ messages[-1], messages[-(MESSAGE_CACHE_LOOKBACK + 1)] ].compact.uniq
    targets.each do |message|
      blocks = message[:content]
      next unless blocks.is_a?(Array)

      last_block = blocks.last
      last_block[:cache_control] = { type: "ephemeral" } if last_block.is_a?(Hash)
    end
  end
end

RubyLLM::Providers::Anthropic.prepend(RubyLLMAnthropicCachePatch)
