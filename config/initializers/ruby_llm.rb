RubyLLM.configure do |config|
  config.perplexity_api_key = Rails.application.credentials.perplexity_api_key || ENV["PERPLEXITY_API_KEY"]
  config.anthropic_api_key  = Rails.application.credentials.anthropic_api_key  || ENV["ANTHROPIC_API_KEY"]
  config.default_model = "claude-3-5-haiku"
  config.logger = Rails.logger
end
