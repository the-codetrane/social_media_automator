# frozen_string_literal: true

require "net/http"
require "json"

# Fetches authoritative usage and cost data from the Anthropic Admin API.
# Both endpoints require an Admin API key (sk-ant-admin…) stored at
# Rails.application.credentials.anthropic_admin_api_key or ENV["ANTHROPIC_ADMIN_KEY"].
#
# Results are cached for 5 minutes. Data from Anthropic is typically available
# within 5 minutes of request completion.
class AnthropicUsageService
  BASE_URL          = "https://api.anthropic.com"
  ANTHROPIC_VERSION = "2023-06-01"
  DAYS              = 31
  CACHE_TTL         = 5.minutes
  CACHE_KEY         = "anthropic_usage_v1"

  class ApiError < StandardError; end
  class MissingKeyError < StandardError; end

  def self.fetch
    Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { new.call }
  end

  def call
    raise MissingKeyError, "Set anthropic_api_key in Rails credentials or ANTHROPIC_API_KEY env var" unless admin_key.present?

    starting_at = DAYS.days.ago.beginning_of_day.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    ending_at   = Time.current.end_of_day.utc.strftime("%Y-%m-%dT%H:%M:%SZ")

    usage_data = fetch_usage(starting_at:, ending_at:)
    cost_data  = fetch_costs(starting_at:, ending_at:)

    build_result(usage_data, cost_data)
  end

  private

  def admin_key
    @admin_key ||= Rails.application.credentials.anthropic_admin_api_key ||
                   Rails.application.credentials.anthropic_api_key ||
                   ENV["ANTHROPIC_ADMIN_KEY"] ||
                   ENV["ANTHROPIC_API_KEY"]
  end

  def fetch_usage(starting_at:, ending_at:)
    paginate("/v1/organizations/usage_report/messages",
      [ "starting_at", starting_at ],
      [ "ending_at",   ending_at ],
      [ "bucket_width", "1d" ],
      [ "limit",       DAYS ],
      [ "group_by[]",  "model" ]
    ) do |bucket|
      date = bucket["starting_at"][0..9]
      bucket["results"].filter_map do |r|
        next if r["model"].blank?
        { date:, model: r["model"], usage: r }
      end
    end
  end

  def fetch_costs(starting_at:, ending_at:)
    paginate("/v1/organizations/cost_report",
      [ "starting_at", starting_at ],
      [ "ending_at",   ending_at ],
      [ "bucket_width", "1d" ],
      [ "limit",       DAYS ],
      [ "group_by[]",  "description" ]
    ) do |bucket|
      date = bucket["starting_at"][0..9]
      bucket["results"].filter_map do |r|
        next if r["model"].blank? || r["cost_type"] != "tokens"
        { date:, model: r["model"], amount_cents: r["amount"].to_f }
      end
    end
  end

  def paginate(path, *base_params, &block)
    results = []
    page    = nil

    loop do
      params = base_params.dup
      params << [ "page", page ] if page

      body = get_json(path, params)
      body["data"].each { |bucket| results.concat(block.call(bucket)) }

      break unless body["has_more"]
      page = body["next_page"]
    end

    results
  end

  def build_result(usage_data, cost_data)
    cost_by_key = Hash.new(0.0)
    cost_data.each { |c| cost_by_key[[ c[:date], c[:model] ]] += c[:amount_cents] }

    daily_rows = usage_data.map do |item|
      u = item[:usage]
      {
        day:               item[:date],
        model_name:        item[:model],
        total_input:       u["uncached_input_tokens"].to_i,
        total_output:      u["output_tokens"].to_i,
        total_cache_read:  u["cache_read_input_tokens"].to_i,
        total_cache_write: u.dig("cache_creation", "ephemeral_5m_input_tokens").to_i +
                           u.dig("cache_creation", "ephemeral_1h_input_tokens").to_i,
        cost:              cost_by_key[[ item[:date], item[:model] ]] / 100.0
      }
    end.sort_by { |r| [ -r[:day], r[:model_name] ] }

    by_model = daily_rows
      .group_by { |r| r[:model_name] }
      .transform_values { |rows| aggregate(rows) }
      .sort_by { |_, v| -v[:cost] }

    totals = aggregate(daily_rows)

    month_start   = Time.current.beginning_of_month.strftime("%Y-%m-%d")
    monthly_rows  = daily_rows.select { |r| r[:day] >= month_start }
    monthly_cost  = monthly_rows.sum { |r| r[:cost] }

    { daily_rows:, by_model:, totals:, monthly_cost:, monthly_rows: }
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

  def get_json(path, params)
    uri       = URI("#{BASE_URL}#{path}")
    uri.query = URI.encode_www_form(params)

    req                     = Net::HTTP::Get.new(uri)
    req["x-api-key"]        = admin_key
    req["anthropic-version"] = ANTHROPIC_VERSION

    resp = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }

    unless resp.is_a?(Net::HTTPSuccess)
      raise ApiError, "HTTP #{resp.code}: #{resp.body.truncate(300)}"
    end

    JSON.parse(resp.body)
  end
end
