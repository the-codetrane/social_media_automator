import { Controller } from "@hotwired/stimulus"

// Autoscrolls the message log to the bottom whenever messages are added
// (initial render, Turbo Stream broadcasts, or thinking indicator).
export default class extends Controller {
  static targets = ["log"]

  connect() {
    this.scrollToBottom()
    this.observer = new MutationObserver(() => this.scrollToBottom())
    this.observer.observe(this.logTarget, { childList: true, subtree: true })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  scrollToBottom() {
    this.logTarget.scrollTop = this.logTarget.scrollHeight
  }
}
