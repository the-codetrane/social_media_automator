import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  connect() {
    this._clickOutside = this._clickOutside.bind(this)
  }

  toggle() {
    this.menuTarget.classList.contains("hidden") ? this._open() : this._close()
  }

  _open() {
    this.menuTarget.classList.remove("hidden")
    document.addEventListener("click", this._clickOutside)
  }

  _close() {
    this.menuTarget.classList.add("hidden")
    document.removeEventListener("click", this._clickOutside)
  }

  _clickOutside(event) {
    if (!this.element.contains(event.target)) this._close()
  }

  disconnect() {
    document.removeEventListener("click", this._clickOutside)
  }
}
