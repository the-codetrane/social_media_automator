RubyLLM.configure do |config|
  config.perplexity_api_key = Rails.application.credentials.perplexity_api_key || ENV["PERPLEXITY_API_KEY"]
  config.anthropic_api_key  = Rails.application.credentials.anthropic_api_key  || ENV["ANTHROPIC_API_KEY"]
  config.default_model = "claude-sonnet-4-6"
  config.logger = Rails.logger
end

# Inject Anthropic prompt-caching breakpoints into every API call.
#
# Anthropic caches any prefix whose last block carries cache_control: {type: "ephemeral"}.
# We mark two stable prefixes:
#   1. The last tool definition  — tool schemas don't change between turns.
#   2. The last system block     — the agent instructions are the same for every turn in a session.
#
# Effect: after the first request, those tokens are served from cache at 0.1× the input price
# instead of 1.0× — roughly 10× cheaper for the stable prefix on every subsequent turn.
module RubyLLMAnthropicCachePatch
  private

  def render_payload(messages, tools:, temperature:, model:, stream: false,
                     schema: nil, thinking: nil, tool_prefs: nil)
    payload = super

    payload[:tools]&.last&.merge!(cache_control: { type: "ephemeral" })

    if (last_text = payload[:system]&.reverse&.find { |b| b.is_a?(Hash) && b[:type] == "text" })
      last_text[:cache_control] = { type: "ephemeral" }
    end

    payload
  end
end

RubyLLM::Providers::Anthropic.prepend(RubyLLMAnthropicCachePatch)
