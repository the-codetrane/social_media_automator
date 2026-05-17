import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["slide", "dot"]
  static values = { index: { type: Number, default: 0 } }

  connect() {
    this.showSlide(this.indexValue)
  }

  prev() {
    const count = this.slideTargets.length
    this.indexValue = (this.indexValue - 1 + count) % count
  }

  next() {
    const count = this.slideTargets.length
    this.indexValue = (this.indexValue + 1) % count
  }

  goTo(event) {
    this.indexValue = parseInt(event.currentTarget.dataset.index)
  }

  indexValueChanged(value) {
    this.showSlide(value)
  }

  showSlide(index) {
    this.slideTargets.forEach((slide, i) => {
      slide.classList.toggle("hidden", i !== index)
    })
    this.dotTargets.forEach((dot, i) => {
      dot.classList.toggle("bg-white", i === index)
      dot.classList.toggle("bg-white/50", i !== index)
    })
  }
}
