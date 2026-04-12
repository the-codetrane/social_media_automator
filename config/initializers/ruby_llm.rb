RubyLLM.configure do |config|
  config.perplexity_api_key = ENV.fetch("PERPLEXITY_API_KEY", Rails.application.credentials.dig(:perplexity_api_key))
  # config.default_model = "gpt-5-nano"

  # Use the new association-based acts_as API (recommended)
  config.use_new_acts_as = true
end
