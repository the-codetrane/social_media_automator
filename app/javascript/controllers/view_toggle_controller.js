import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["cardView", "tableView", "cardButton", "tableButton", "cardInput", "tableInput"]
  static values = { storageKey: String }

  connect() {
    this.applyView()
  }

  applyView() {
    const view = localStorage.getItem(this.storageKeyValue) || "card"
    this.#setView(view)
  }

  // Radio inputs (a ToggleGroup): the checked value is the view.
  select(event) {
    if (event.target.value === "table") this.showTable()
    else this.showCard()
  }

  showCard() {
    localStorage.setItem(this.storageKeyValue, "card")
    this.#setView("card")
    this.#resetBulkSelect()
  }

  showTable() {
    localStorage.setItem(this.storageKeyValue, "table")
    this.#setView("table")
    this.#resetBulkSelect()
  }

  #setView(view) {
    const isTable = view === "table"
    this.cardViewTargets.forEach(el => el.classList.toggle("hidden", isTable))
    this.tableViewTargets.forEach(el => el.classList.toggle("hidden", !isTable))
    if (this.hasCardInputTarget) this.cardInputTarget.checked = !isTable
    if (this.hasTableInputTarget) this.tableInputTarget.checked = isTable
    if (this.hasCardInputTarget || this.hasTableInputTarget) this.#syncSelectionInputs(isTable)
    if (this.hasCardButtonTarget) {
      this.cardButtonTarget.classList.toggle("bg-white", !isTable)
      this.cardButtonTarget.classList.toggle("shadow-sm", !isTable)
      this.cardButtonTarget.classList.toggle("text-gray-700", !isTable)
      this.cardButtonTarget.classList.toggle("text-gray-400", isTable)
    }
    if (this.hasTableButtonTarget) {
      this.tableButtonTarget.classList.toggle("bg-white", isTable)
      this.tableButtonTarget.classList.toggle("shadow-sm", isTable)
      this.tableButtonTarget.classList.toggle("text-gray-700", isTable)
      this.tableButtonTarget.classList.toggle("text-gray-400", !isTable)
    }
  }

  // The hidden view's selection checkboxes are disabled so cl-bulk-select neither counts nor submits them twice.
  #syncSelectionInputs(isTable) {
    let changed
    this.cardViewTargets.forEach(el => el.querySelectorAll("[data-cl-bulk-select-target='item']").forEach(cb => { cb.disabled = isTable; changed = cb }))
    this.tableViewTargets.forEach(el => el.querySelectorAll("[data-cl-bulk-select-target='item']").forEach(cb => { cb.disabled = !isTable; changed = cb }))
    if (changed) changed.dispatchEvent(new Event("change", { bubbles: true }))
  }

  #resetBulkSelect() {
    this.element.querySelectorAll("[data-bulk-select-target='checkbox']:checked, [data-cl-bulk-select-target='item']:checked").forEach(cb => {
      cb.checked = false
      cb.dispatchEvent(new Event("change", { bubbles: true }))
    })
  }
}
