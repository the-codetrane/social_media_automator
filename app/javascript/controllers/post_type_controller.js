import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["singleSection", "carouselSection"]

  connect() {
    this.update()
  }

  update() {
    const isCarousel = this.element.querySelector("input[value='carousel']")?.checked ?? false
    this.singleSectionTarget.classList.toggle("hidden", isCarousel)
    this.carouselSectionTarget.classList.toggle("hidden", !isCarousel)
  }
}
