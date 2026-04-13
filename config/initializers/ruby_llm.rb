RubyLLM.configure do |config|
  config.perplexity_api_key = ENV.fetch("PERPLEXITY_API_KEY", Rails.application.credentials.dig(:perplexity_api_key))
  config.default_model = "sonar-pro"
  config.logger = Rails.logger
end
