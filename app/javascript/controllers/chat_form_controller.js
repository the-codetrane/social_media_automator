import { Controller } from "@hotwired/stimulus"

// Handles the chat input: Enter-to-submit (Shift+Enter inserts a newline),
// textarea autosize, resetting the field after a successful submit, and
// optional image attachment with inline preview.
export default class extends Controller {
  static targets = ["input", "fileInput", "preview", "previewImage"]

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
      this.clearFilePreview()
    }
  }

  selectFile() {
    this.fileInputTarget.click()
  }

  previewFile() {
    const file = this.fileInputTarget.files[0]
    if (!file) return

    const reader = new FileReader()
    reader.onload = (e) => {
      this.previewImageTarget.src = e.target.result
      this.previewTarget.classList.remove("hidden")
      this.previewTarget.classList.add("flex")
    }
    reader.readAsDataURL(file)
  }

  removeFile() {
    this.fileInputTarget.value = ""
    this.clearFilePreview()
  }

  clearFilePreview() {
    this.previewImageTarget.src = ""
    this.previewTarget.classList.add("hidden")
    this.previewTarget.classList.remove("flex")
  }
}
