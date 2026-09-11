import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["singleSection", "carouselSection", "storyNote", "feedOptions"]

  connect() {
    this.update()
  }

  update() {
    // The carousel picker inside this controller uses checkboxes, so a
    // radio-only selector reads the post type and nothing else.
    const postType = this.element.querySelector("input[type='radio']:checked")?.value ?? "single"

    // A story picks one asset, same as a single post.
    this.singleSectionTarget.classList.toggle("hidden", postType === "carousel")
    this.carouselSectionTarget.classList.toggle("hidden", postType !== "carousel")

    if (this.hasStoryNoteTarget) {
      this.storyNoteTarget.classList.toggle("hidden", postType !== "story")
    }

    // Collaborators and audio are feed-only — Meta ignores both on a story.
    if (this.hasFeedOptionsTarget) {
      this.feedOptionsTarget.classList.toggle("hidden", postType === "story")
    }
  }
}
