# frozen_string_literal: true

require "test_helper"

class LocalLlmTest < ActiveSupport::TestCase
  ENV_KEYS = %w[LOCAL_LLM_URL LOCAL_LLM_MODEL LOCAL_LLM_API_KEY].freeze

  setup do
    @saved_env = ENV.to_h.slice(*ENV_KEYS)
    ENV_KEYS.each { |key| ENV.delete(key) }
  end

  teardown do
    ENV_KEYS.each { |key| ENV.delete(key) }
    @saved_env.each { |key, value| ENV[key] = value }
  end

  def in_development(&)
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("development"), &)
  end

  test "is off in development until LOCAL_LLM_URL is set" do
    in_development { assert_not LocalLlm.enabled? }
  end

  test "is on in development once LOCAL_LLM_URL is set" do
    ENV["LOCAL_LLM_URL"] = "http://127.0.0.1:8080"

    in_development { assert LocalLlm.enabled? }
  end

  test "stays off outside development even with LOCAL_LLM_URL set" do
    ENV["LOCAL_LLM_URL"] = "http://127.0.0.1:8080"

    assert_not LocalLlm.enabled?, "test environment must never route to a local server"
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("production")) do
      assert_not LocalLlm.enabled?
    end
  end

  test "accepts the server URL with or without a /v1 suffix" do
    [ "http://127.0.0.1:8080", "http://127.0.0.1:8080/", "http://127.0.0.1:8080/v1", "http://127.0.0.1:8080/v1/" ].each do |url|
      ENV["LOCAL_LLM_URL"] = url
      assert_equal "http://127.0.0.1:8080", LocalLlm.url, "for #{url}"
    end
  end

  test "defaults the model to llama-server's qwen-local alias and allows an override" do
    assert_equal "qwen-local", LocalLlm.model_id

    ENV["LOCAL_LLM_MODEL"] = "qwen3.8-27b"
    assert_equal "qwen3.8-27b", LocalLlm.model_id
  end

  test "context points Anthropic requests at the local server without touching the global config" do
    ENV["LOCAL_LLM_URL"] = "http://127.0.0.1:8080"
    original_base = RubyLLM.config.anthropic_api_base
    RubyLLM.config.anthropic_api_base = "https://global.example"

    context = LocalLlm.context

    assert_equal "http://127.0.0.1:8080", context.config.anthropic_api_base
    assert_equal "local", context.config.anthropic_api_key
    assert_equal "https://global.example", RubyLLM.config.anthropic_api_base
  ensure
    RubyLLM.config.anthropic_api_base = original_base
  end
end
