# frozen_string_literal: true

# Points the chat agent at a local model server instead of Anthropic during development,
# so day-to-day work on the chat flow doesn't spend API credits.
#
# The target is any server that speaks the Anthropic Messages API — in practice llama.cpp's
# llama-server running Qwen3-Coder-Next:
#
#   llama-server -hf unsloth/Qwen3-Coder-Next-GGUF:UD-Q6_K_XL --alias qwen-local --jinja \
#     -c 131072 --temp 1.0 --top-p 0.95 --top-k 40 --min-p 0.01 --port 8080
#   LOCAL_LLM_URL=http://127.0.0.1:8080 bin/dev
#
# Speaking Anthropic's protocol keeps the request shape (messages, tool blocks, tool results)
# identical to production, so what works locally is what ships. Off unless LOCAL_LLM_URL is
# set, and never on outside development, whatever the environment says.
#
# Only the chat agent is rerouted. The Vision services stay on Anthropic: the local model is
# text-only, and they build Anthropic-specific image payloads.
module LocalLlm
  DEFAULT_MODEL = "qwen-local"

  module_function

  def enabled?
    Rails.env.development? && url.present?
  end

  # Base URL of the local server, without /v1 (RubyLLM appends the path).
  def url
    ENV["LOCAL_LLM_URL"].presence&.delete_suffix("/")&.delete_suffix("/v1")
  end

  # The name the server answers to: llama-server's --alias.
  def model_id
    ENV.fetch("LOCAL_LLM_MODEL", DEFAULT_MODEL)
  end

  # An isolated RubyLLM configuration for the local server. The global configuration — and
  # with it the Anthropic key the Vision services use — is left untouched.
  def context
    RubyLLM.context do |config|
      config.anthropic_api_base = url
      # llama-server doesn't check keys unless started with --api-key; RubyLLM still requires one.
      config.anthropic_api_key  = ENV.fetch("LOCAL_LLM_API_KEY", "local")
    end
  end

  # The entry the chat model picker shows while local mode is on.
  def model_entry
    {
      id: model_id,
      display_name: "Local Qwen",
      tagline: "Development only — #{url}",
      description: "Served by your local llama-server. No API cost, so it's the default for building and testing the chat flow.",
      strengths: [ "No API spend", "Same request shape as production", "Nothing leaves your machine" ],
      limitations: [ "Weaker writing than Claude", "Text only — no image understanding" ]
    }
  end
end
