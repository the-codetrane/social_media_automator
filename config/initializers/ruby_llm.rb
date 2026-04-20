RubyLLM.configure do |config|
  config.perplexity_api_key = Rails.application.credentials.perplexity_api_key || ENV["PERPLEXITY_API_KEY"]
  config.anthropic_api_key  = Rails.application.credentials.anthropic_api_key  || ENV["ANTHROPIC_API_KEY"]
  config.default_model = "sonar-pro"
  config.logger = Rails.logger
end
