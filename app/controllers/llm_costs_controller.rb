# frozen_string_literal: true

class LlmCostsController < ApplicationController
  # Pricing per million tokens (USD). Cache write assumes the 5-minute TTL (1.25× input).
  PRICING = {
    "claude-sonnet-4-6"         => { input: 3.00,  output: 15.00, cache_read: 0.30, cache_write: 3.75 },
    "claude-haiku-4-5-20251001" => { input: 1.00,  output:  5.00, cache_read: 0.10, cache_write: 1.25 },
    "claude-haiku-4-5"          => { input: 1.00,  output:  5.00, cache_read: 0.10, cache_write: 1.25 },
    "claude-opus-4-7"           => { input: 5.00,  output: 25.00, cache_read: 0.50, cache_write: 6.25 },
    "claude-opus-4-6"           => { input: 5.00,  output: 25.00, cache_read: 0.50, cache_write: 6.25 },
    "sonar-pro"                 => { input: 3.00,  output: 15.00, cache_read: 0.00, cache_write: 0.00 }
  }.freeze

  def index
    raw = Message
      .where(role: "assistant")
      .where.not(input_tokens: nil)
      .joins(:model)
      .group("date(messages.created_at)", "models.model_id")
      .select(
        "date(messages.created_at) as day",
        "models.model_id as model_name",
        "sum(messages.input_tokens) as total_input",
        "sum(messages.output_tokens) as total_output",
        "coalesce(sum(messages.cached_tokens), 0) as total_cache_read",
        "coalesce(sum(messages.cache_creation_tokens), 0) as total_cache_write",
        "count(*) as response_count"
      )
      .order("day desc")

    @daily_rows = raw.map { |r| r.attributes.symbolize_keys.merge(cost: calculate_cost(r)) }

    @by_model = @daily_rows
      .group_by { |r| r[:model_name] }
      .transform_values { |rows| aggregate(rows) }
      .sort_by { |_, v| -v[:cost] }

    @totals = aggregate(@daily_rows)

    @cache_savings = @daily_rows.sum { |r| calculate_cache_savings(r) }

    month_start = Time.current.beginning_of_month
    @monthly_rows = @daily_rows.select { |r| r[:day].to_s >= month_start.strftime("%Y-%m-%d") }
    @monthly_cost = @monthly_rows.sum { |r| r[:cost] }
  end

  private

  def calculate_cost(row)
    pricing = PRICING[row["model_name"]] || { input: 0, output: 0, cache_read: 0, cache_write: 0 }
    (row.total_input.to_i        * pricing[:input]       +
     row.total_output.to_i       * pricing[:output]      +
     row.total_cache_read.to_i   * pricing[:cache_read]  +
     row.total_cache_write.to_i  * pricing[:cache_write]) / 1_000_000.0
  end

  def calculate_cache_savings(row)
    pricing = PRICING[row[:model_name]]
    return 0.0 unless pricing
    row[:total_cache_read].to_i * (pricing[:input] - pricing[:cache_read]) / 1_000_000.0
  end

  def aggregate(rows)
    {
      response_count:    rows.sum { |r| r[:response_count].to_i },
      total_input:       rows.sum { |r| r[:total_input].to_i },
      total_output:      rows.sum { |r| r[:total_output].to_i },
      total_cache_read:  rows.sum { |r| r[:total_cache_read].to_i },
      total_cache_write: rows.sum { |r| r[:total_cache_write].to_i },
      cost:              rows.sum { |r| r[:cost] }
    }
  end
end
