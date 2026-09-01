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
#
# Every mutation below is copy-on-write (never `merge!`/`[]=` on an object we didn't just
# allocate). RubyLLM's internal message/content hashes may be memoized or shared across
# concurrent requests in a threaded server, so mutating them in place risks both stale
# cache_control markers accumulating past Anthropic's 4-breakpoint limit as history grows,
# and cross-request data races.
module RubyLLMAnthropicCachePatch
  # How far back the second (fallback) message breakpoint sits from the end of the history.
  MESSAGE_CACHE_LOOKBACK = 4

  CACHE_CONTROL = { type: "ephemeral" }.freeze

  private

  def render_payload(messages, tools:, temperature:, model:, stream: false,
                     schema: nil, thinking: nil, tool_prefs: nil)
    payload = super

    if payload[:tools].present?
      tools = payload[:tools].dup
      tools[-1] = tools.last.merge(cache_control: CACHE_CONTROL)
      payload[:tools] = tools
    end

    if payload[:system].present?
      idx = payload[:system].rindex { |b| b.is_a?(Hash) && b[:type] == "text" }
      if idx
        system = payload[:system].dup
        system[idx] = system[idx].merge(cache_control: CACHE_CONTROL)
        payload[:system] = system
      end
    end

    # Must run before the breakpoints are placed: coalescing changes message indices,
    # and a marked message could otherwise be merged away.
    payload[:messages] = mark_message_breakpoints(coalesce_tool_results(payload[:messages]))

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
  # Anything mixed (text alongside results) is left alone. The `.present?` guard matters:
  # without it, `[].all? { ... }` is vacuously true and an empty-content message would be
  # misclassified as a tool-result message.
  def tool_result_message?(message)
    return false unless message.is_a?(Hash)
    return false unless message[:role].to_s == "user"

    blocks = message[:content]
    blocks.is_a?(Array) && blocks.present? &&
      blocks.all? { |b| b.is_a?(Hash) && b[:type].to_s == "tool_result" }
  end

  # Mark the trailing messages so the accumulated history is served from cache.
  # Content is an array of blocks; cache_control goes on the last block of the message.
  #
  # Returns a new array/hashes at the touched positions only — every other message keeps
  # its original object reference, so this never mutates anything the caller still holds.
  def mark_message_breakpoints(messages)
    return messages if messages.blank?

    target_indices = [ messages.length - 1, messages.length - MESSAGE_CACHE_LOOKBACK - 1 ]
                       .select { |i| i >= 0 }
                       .uniq

    return messages if target_indices.empty?

    messages = messages.dup
    target_indices.each do |i|
      blocks = messages[i][:content]
      next unless blocks.is_a?(Array) && blocks.last.is_a?(Hash)

      blocks = blocks.dup
      blocks[-1] = blocks[-1].merge(cache_control: CACHE_CONTROL)
      messages[i] = messages[i].merge(content: blocks)
    end

    messages
  end
end

RubyLLM::Providers::Anthropic.prepend(RubyLLMAnthropicCachePatch)
