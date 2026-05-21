import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle", "title"]
  static values = {
    daily: Array,
    weekly: Array,
    monthly: Array,
    chartId: String
  }

  connect() {
    this.activePeriod = "weekly"
  }

  switch(event) {
    const period = event.currentTarget.dataset.period
    if (period === this.activePeriod) return

    this.activePeriod = period
    this.#updateToggles(period)
    this.#updateTitle(period)
    this.#updateChart(period)
  }

  #updateToggles(period) {
    this.toggleTargets.forEach(btn => {
      const active = btn.dataset.period === period
      btn.classList.toggle("bg-indigo-600", active)
      btn.classList.toggle("text-white", active)
      btn.classList.toggle("bg-white", !active)
      btn.classList.toggle("text-gray-600", !active)
    })
  }

  #updateTitle(period) {
    const labels = { daily: "Daily", weekly: "Weekly", monthly: "Monthly" }
    this.titleTarget.textContent = `${labels[period]} Performance`
  }

  #updateChart(period) {
    const dataMap = { daily: this.dailyValue, weekly: this.weeklyValue, monthly: this.monthlyValue }
    const chart = Chartkick.charts[this.chartIdValue]
    if (chart) chart.updateData(dataMap[period])
  }
}
