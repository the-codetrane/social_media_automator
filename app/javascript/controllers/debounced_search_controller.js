import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    delay: { type: Number, default: 300 },
    minLength: { type: Number, default: 3 }
  }

  connect() {
    this.timer = null
  }

  search(event) {
    clearTimeout(this.timer)
    const value = event.target.value
    if (value.length === 0 || value.length >= this.minLengthValue) {
      this.timer = setTimeout(() => this.element.requestSubmit(), this.delayValue)
    }
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
