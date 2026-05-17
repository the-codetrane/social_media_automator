import { Controller } from "@hotwired/stimulus"

// Handles the chat input: Enter-to-submit (Shift+Enter inserts a newline),
// textarea autosize, and resetting the field after a successful submit.
export default class extends Controller {
  static targets = ["input"]

  submitOnEnter(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      if (this.inputTarget.value.trim().length === 0) return
      this.element.requestSubmit()
    }
  }

  autosize() {
    const el = this.inputTarget
    el.style.height = "auto"
    el.style.height = `${el.scrollHeight}px`
  }

  reset(event) {
    if (event.detail.success) {
      this.inputTarget.value = ""
      this.inputTarget.style.height = "auto"
      this.inputTarget.focus()
    }
  }
}
