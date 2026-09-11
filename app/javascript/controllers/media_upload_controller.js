import { Controller } from "@hotwired/stimulus"
import { DirectUpload } from "@rails/activestorage"

// Upload form for Media Assets. Files go straight from the browser to storage
// via ActiveStorage direct uploads; the blob is filed under the chosen folder
// by MediaAssets::DirectUploadsController. Once every file has landed the form
// is submitted with the resulting signed blob ids so the server can create the
// MediaAsset records.
export default class extends Controller {
  static targets = ["folderSelect", "newFolderInput", "fileInput", "fileList", "error", "submit"]
  static values = { directUploadUrl: String }

  static NEW_FOLDER = "__new__"

  folderChanged() {
    const creating = this.folderSelectTarget.value === this.constructor.NEW_FOLDER
    this.newFolderInputTarget.classList.toggle("hidden", !creating)
    this.newFolderInputTarget.required = creating
    if (creating) this.newFolderInputTarget.focus()
  }

  filesChanged() {
    this._hideError()
    this.fileListTarget.innerHTML = ""
    this._rows = new Map()

    for (const file of this.fileInputTarget.files) {
      const row = this._buildRow(file)
      this._rows.set(file, row)
      this.fileListTarget.appendChild(row.element)
    }
  }

  async submit(event) {
    // Second pass: uploads are done and the signed ids are in the form.
    if (this._uploaded) return

    event.preventDefault()
    this._hideError()

    const folder = this._folder()
    const files = Array.from(this.fileInputTarget.files)

    if (!folder) return this._showError("Choose a destination folder.")
    if (files.length === 0) return this._showError("Select at least one photo or video.")

    this._setBusy(true)

    try {
      const signedIds = await Promise.all(files.map(file => this._upload(file, folder)))
      signedIds.forEach(id => this._appendHidden("media_asset[signed_ids][]", id))

      // The raw file input must not be posted — the bytes are already in storage.
      this.fileInputTarget.disabled = true
      this.folderSelectTarget.disabled = true
      this.newFolderInputTarget.disabled = true

      this._uploaded = true
      this.element.requestSubmit()
    } catch (error) {
      this._showError(error.message || "Upload failed. Please try again.")
      this._setBusy(false)
    }
  }

  // -- private ---------------------------------------------------------------

  _folder() {
    const selected = this.folderSelectTarget.value
    if (selected === this.constructor.NEW_FOLDER) return this.newFolderInputTarget.value.trim()
    return selected
  }

  _upload(file, folder) {
    const url = `${this.directUploadUrlValue}?folder=${encodeURIComponent(folder)}`
    const row = this._rows?.get(file)

    return new Promise((resolve, reject) => {
      const upload = new DirectUpload(file, url, {
        directUploadWillStoreFileWithXHR: (xhr) => {
          xhr.upload.addEventListener("progress", event => {
            if (event.lengthComputable && row) row.setProgress(event.loaded / event.total)
          })
        }
      })

      upload.create((error, blob) => {
        if (error) {
          row?.setFailed()
          reject(new Error(`${file.name}: ${error}`))
        } else {
          row?.setProgress(1)
          resolve(blob.signed_id)
        }
      })
    })
  }

  _buildRow(file) {
    const element = document.createElement("li")
    element.className = "flex flex-col gap-1"

    const label = document.createElement("div")
    label.className = "flex items-center justify-between gap-3"
    label.innerHTML = `
      <span class="truncate text-gray-700">${this._escape(file.name)}</span>
      <span class="shrink-0 text-xs text-gray-400">${this._formatSize(file.size)}</span>`

    const track = document.createElement("div")
    track.className = "h-1.5 w-full rounded-full bg-gray-100 overflow-hidden"
    const bar = document.createElement("div")
    bar.className = "h-full w-0 bg-indigo-500 transition-[width] duration-150"
    track.appendChild(bar)

    element.append(label, track)

    return {
      element,
      setProgress(fraction) { bar.style.width = `${Math.round(fraction * 100)}%` },
      setFailed() { bar.classList.replace("bg-indigo-500", "bg-red-500"); bar.style.width = "100%" }
    }
  }

  _appendHidden(name, value) {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = name
    input.value = value
    this.element.appendChild(input)
  }

  _setBusy(busy) {
    this.submitTarget.disabled = busy
    this.submitTarget.value = busy ? "Uploading…" : "Upload"
  }

  _showError(message) {
    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("hidden")
  }

  _hideError() {
    this.errorTarget.classList.add("hidden")
  }

  _formatSize(bytes) {
    if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
  }

  _escape(text) {
    const span = document.createElement("span")
    span.textContent = text
    return span.innerHTML
  }
}
