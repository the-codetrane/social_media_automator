# frozen_string_literal: true

class LlmCostsController < ApplicationController
  def index
    result = LocalLlmUsageService.fetch

    @daily_rows   = result[:daily_rows]
    @by_model     = result[:by_model]
    @totals       = result[:totals]
    @monthly_cost = result[:monthly_cost]
    @monthly_rows = result[:monthly_rows]
  rescue => e
    @error = e.message
    set_empty_state
  end

  private

  def set_empty_state
    @daily_rows   = []
    @by_model     = []
    @totals       = { total_input: 0, total_output: 0, total_cache_read: 0, total_cache_write: 0, cost: 0.0 }
    @monthly_cost = 0.0
    @monthly_rows = []
  end
end
