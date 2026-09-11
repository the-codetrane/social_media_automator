import { Controller } from "@hotwired/stimulus"

// Wraps a native <dialog>. Open it from any event (e.g. a Turbo frame finishing
// its load) and close it from buttons inside, Escape, or a backdrop click.
export default class extends Controller {
  open() {
    if (!this.element.open) this.element.showModal()
  }

  close() {
    if (this.element.open) this.element.close()
  }

  // <dialog> receives the click when the backdrop is hit; clicks on content
  // bubble up with a different target.
  closeOnBackdrop(event) {
    if (event.target === this.element) this.close()
  }
}
