# frozen_string_literal: true

# Computes LLM usage and estimated cost from locally stored Message records.
# Replaces AnthropicUsageService for accounts without an Anthropic Admin API key.
class LocalLlmUsageService
  DAYS      = 31
  CACHE_TTL = 5.minutes
  CACHE_KEY = "local_llm_usage_v1"

  # Pricing in USD per 1M tokens.
  # cache_write = 5-minute ephemeral TTL (1.25× input).
  # cache_read  = 0.1× input.
  PRICING = {
    # Anthropic
    /claude-haiku-4-5/    => { input: 1.00,  output: 5.00,  cache_read: 0.10, cache_write: 1.25 },
    /claude-haiku-3/      => { input: 0.25,  output: 1.25,  cache_read: 0.03, cache_write: 0.30 },
    /claude-sonnet-4-6/   => { input: 3.00,  output: 15.00, cache_read: 0.30, cache_write: 3.75 },
    /claude-sonnet-4-5/   => { input: 3.00,  output: 15.00, cache_read: 0.30, cache_write: 3.75 },
    /claude-opus-4/       => { input: 5.00,  output: 25.00, cache_read: 0.50, cache_write: 6.25 },
    # Perplexity
    /sonar-pro/           => { input: 3.00,  output: 15.00, cache_read: 0.00, cache_write: 0.00 },
    /sonar/               => { input: 1.00,  output: 5.00,  cache_read: 0.00, cache_write: 0.00 }
  }.freeze

  PER_MILLION = 1_000_000.0

  def self.fetch
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { new.call }
  end

  def call
    since = DAYS.days.ago.beginning_of_day

    rows = Message
      .joins(:model)
      .where(role: "assistant")
      .where("messages.created_at >= ?", since)
      .where("messages.input_tokens IS NOT NULL OR messages.output_tokens IS NOT NULL")
      .select(
        "DATE(messages.created_at) AS day",
        "models.model_id AS llm_model_id",
        "SUM(COALESCE(messages.input_tokens, 0)) AS total_input",
        "SUM(COALESCE(messages.output_tokens, 0)) AS total_output",
        "SUM(COALESCE(messages.cached_tokens, 0)) AS total_cache_read",
        "SUM(COALESCE(messages.cache_creation_tokens, 0)) AS total_cache_write"
      )
      .group("DATE(messages.created_at)", "models.model_id")
      .map do |r|
        pricing = pricing_for(r.llm_model_id)
        cost = compute_cost(
          r.total_input, r.total_output,
          r.total_cache_read, r.total_cache_write,
          pricing
        )
        {
          day:               r.day.to_s,
          model_name:        r.llm_model_id,
          total_input:       r.total_input.to_i,
          total_output:      r.total_output.to_i,
          total_cache_read:  r.total_cache_read.to_i,
          total_cache_write: r.total_cache_write.to_i,
          cost:              cost
        }
      end
      .sort_by { |r| [ -r[:day].delete("-").to_i, r[:model_name] ] }

    by_model = rows
      .group_by { |r| r[:model_name] }
      .transform_values { |model_rows| aggregate(model_rows) }
      .sort_by { |_, v| -v[:cost] }

    totals = aggregate(rows)

    month_start  = Time.current.beginning_of_month.strftime("%Y-%m-%d")
    monthly_rows = rows.select { |r| r[:day] >= month_start }
    monthly_cost = monthly_rows.sum { |r| r[:cost] }

    { daily_rows: rows, by_model:, totals:, monthly_cost:, monthly_rows: }
  end

  private

  def pricing_for(model_id)
    PRICING.each { |pattern, prices| return prices if model_id.to_s.match?(pattern) }
    { input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0 }
  end

  def compute_cost(input, output, cache_read, cache_write, pricing)
    (input.to_f  * pricing[:input]       +
     output.to_f * pricing[:output]      +
     cache_read.to_f  * pricing[:cache_read]  +
     cache_write.to_f * pricing[:cache_write]) / PER_MILLION
  end

  def aggregate(rows)
    {
      total_input:       rows.sum { |r| r[:total_input] },
      total_output:      rows.sum { |r| r[:total_output] },
      total_cache_read:  rows.sum { |r| r[:total_cache_read] },
      total_cache_write: rows.sum { |r| r[:total_cache_write] },
      cost:              rows.sum { |r| r[:cost] }
    }
  end
end
