RubyLLM.configure do |config|
  config.perplexity_api_key = Rails.application.credentials.perplexity_api_key || ENV["PERPLEXITY_API_KEY"]
  config.anthropic_api_key  = if Rails.env.production?
                                Rails.application.credentials.anthropic_api_key || ENV["ANTHROPIC_API_KEY"]
  else
                                ENV["ANTHROPIC_API_KEY"] || Rails.application.credentials.anthropic_api_key
  end
  config.default_model = "claude-sonnet-5"
  config.logger = Rails.logger
end
