module LlmCostsHelper
  def format_llm_cost(amount)
    return "$0.00" if amount.nil? || amount.zero?

    if amount < 0.001
      "< $0.001"
    elsif amount < 1.0
      "$#{format("%.4f", amount)}"
    else
      "$#{format("%.2f", amount)}"
    end
  end
end
