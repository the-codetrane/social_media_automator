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
    // Radios of a ToggleGroup: keep the checked option in step with the stored view.
    if (this.hasCardInputTarget) this.cardInputTarget.checked = !isTable
    if (this.hasTableInputTarget) this.tableInputTarget.checked = isTable
    // The hidden view's cl-bulk-select checkboxes are disabled so select-all, the
    // count and the submitted ids only cover what is on screen.
    this.#setItemsDisabled(this.cardViewTargets, isTable)
    this.#setItemsDisabled(this.tableViewTargets, !isTable)
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

  #setItemsDisabled(views, disabled) {
    views.forEach(view => {
      view.querySelectorAll("[data-cl-bulk-select-target~='item']").forEach(cb => { cb.disabled = disabled })
    })
  }

  #resetBulkSelect() {
    this.element.querySelectorAll("[data-bulk-select-target='checkbox']:checked, [data-cl-bulk-select-target~='item']:checked").forEach(cb => {
      cb.checked = false
      cb.dispatchEvent(new Event("change", { bubbles: true }))
    })
  }
}
