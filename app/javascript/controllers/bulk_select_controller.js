import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "checkbox", "actionBar", "countLabel",
    "rescheduleModal", "deleteModal", "deleteCount"
  ]
  // Name of the array param the selected IDs are submitted under.
  static values = { paramName: { type: String, default: "post_ids" } }

  toggle() {
    const count = this.checkedIds.length
    this.actionBarTarget.classList.toggle("hidden", count === 0)
    this.countLabelTarget.textContent = `${count} selected`
  }

  resetSelection() {
    this.checkboxTargets.forEach(cb => { cb.checked = false })
    this.actionBarTarget.classList.add("hidden")
    this.countLabelTarget.textContent = "0 selected"
  }

  deselectAll() {
    this.resetSelection()
  }

  // Reschedule modal
  openRescheduleModal() {
    this.rescheduleModalTarget.classList.remove("hidden")
  }

  closeRescheduleModal() {
    this.rescheduleModalTarget.classList.add("hidden")
  }

  // Delete modal
  openDeleteModal() {
    this.deleteCountTarget.textContent = this.checkedIds.length
    this.deleteModalTarget.classList.remove("hidden")
  }

  closeDeleteModal() {
    this.deleteModalTarget.classList.add("hidden")
  }

  // Close modal when clicking the backdrop (but not the inner panel)
  closeOnBackdrop(event) {
    if (event.target === event.currentTarget) {
      event.currentTarget.classList.add("hidden")
    }
  }

  // Inject selected post IDs into whichever form is being submitted
  injectIds(event) {
    const form = event.currentTarget
    form.querySelectorAll("[data-injected-id]").forEach(el => el.remove())
    this.checkedIds.forEach(id => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = `${this.paramNameValue}[]`
      input.value = id
      input.setAttribute("data-injected-id", "")
      form.appendChild(input)
    })
  }

  get checkedIds() {
    return this.checkboxTargets.filter(cb => cb.checked).map(cb => cb.value)
  }
}
