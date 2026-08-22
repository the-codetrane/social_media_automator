import { Controller } from "@hotwired/stimulus"

// Searchable picker for the track attached to a Reel.
//
// Results come from PlannedPosts#audio_search, which proxies Instagram's Audio
// API. Selecting a track writes its ID into the form; the title and artist ride
// along so the post can name the track without calling Meta again.
export default class extends Controller {
  static targets = ["input", "type", "results", "selected", "picker", "hiddenInputs"]
  static values = {
    url: String,
    initial: Object,
    delay: { type: Number, default: 400 }
  }

  connect() {
    const initial = this.initialValue
    this._track = initial && initial.audio_id ? initial : null
    this._timer = null
    this.render()
  }

  disconnect() {
    clearTimeout(this._timer)
  }

  // ---------------------------------------------------------------------
  // Searching
  // ---------------------------------------------------------------------

  search() {
    clearTimeout(this._timer)
    this._timer = setTimeout(() => this._fetchTracks(), this.delayValue)
  }

  async _fetchTracks() {
    const params = new URLSearchParams({
      q: this.inputTarget.value.trim(),
      audio_type: this.typeTarget.value
    })

    this._renderMessage("Searching…")

    try {
      const response = await fetch(`${this.urlValue}?${params}`, {
        headers: { Accept: "application/json" }
      })
      const data = await response.json()

      if (!response.ok) {
        this._renderMessage(data.error || "Could not reach Instagram.")
        return
      }

      this._renderResults(data.tracks || [])
    } catch {
      this._renderMessage("Could not reach Instagram.")
    }
  }

  // ---------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------

  selectTrack(track) {
    this._track = track
    this.resultsTarget.classList.add("hidden")
    this.inputTarget.value = ""
    this.render()
  }

  clear() {
    this._track = null
    this.render()
  }

  // ---------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------

  render() {
    this._renderSelected()
    this._syncHiddenInputs()
  }

  _renderSelected() {
    const container = this.selectedTarget
    container.innerHTML = ""

    if (!this._track) {
      container.classList.add("hidden")
      this.pickerTarget.classList.remove("hidden")
      return
    }

    container.classList.remove("hidden")
    // One track at a time — hide the search UI until the current one is cleared.
    this.pickerTarget.classList.add("hidden")

    const card = document.createElement("div")
    card.className =
      "flex items-center gap-3 px-3 py-2 bg-indigo-50 border border-indigo-200 rounded-lg"

    card.appendChild(this._artwork(this._track))
    card.appendChild(this._trackLabel(this._track))

    const clear = document.createElement("button")
    clear.type = "button"
    clear.className =
      "shrink-0 px-2 py-1 text-xs font-medium text-indigo-700 hover:text-red-600 transition-colors"
    clear.textContent = "Remove"
    clear.addEventListener("click", () => this.clear())
    card.appendChild(clear)

    container.appendChild(card)
  }

  _renderResults(tracks) {
    const list = this.resultsTarget
    list.innerHTML = ""

    if (tracks.length === 0) {
      this._renderMessage("No audio matched.")
      return
    }

    tracks.forEach(track => {
      const row = document.createElement("button")
      row.type = "button"
      row.className =
        "w-full flex items-center gap-3 px-3 py-2 text-left hover:bg-gray-50 transition-colors"

      row.appendChild(this._artwork(track))
      row.appendChild(this._trackLabel(track))

      if (track.duration) {
        const duration = document.createElement("span")
        duration.className = "shrink-0 text-xs text-gray-400 tabular-nums"
        duration.textContent = track.duration
        row.appendChild(duration)
      }

      row.addEventListener("click", () => this.selectTrack(track))
      list.appendChild(row)
    })

    list.classList.remove("hidden")
  }

  _renderMessage(message) {
    const list = this.resultsTarget
    list.innerHTML = ""

    const note = document.createElement("p")
    note.className = "px-3 py-4 text-sm text-gray-400 text-center"
    note.textContent = message

    list.appendChild(note)
    list.classList.remove("hidden")
  }

  // Track titles come from Meta, so every value is set via textContent.
  _trackLabel(track) {
    const wrapper = document.createElement("span")
    wrapper.className = "flex-1 min-w-0"

    const title = document.createElement("span")
    title.className = "block text-sm text-gray-700 truncate"
    title.textContent = track.title || "Untitled audio"
    wrapper.appendChild(title)

    if (track.artist) {
      const artist = document.createElement("span")
      artist.className = "block text-xs text-gray-400 truncate"
      artist.textContent = track.artist
      wrapper.appendChild(artist)
    }

    return wrapper
  }

  _artwork(track) {
    if (track.thumbnail) {
      const image = document.createElement("img")
      image.src = track.thumbnail
      image.alt = ""
      image.className = "w-9 h-9 rounded object-cover shrink-0 bg-gray-100"
      return image
    }

    const placeholder = document.createElement("span")
    placeholder.className =
      "w-9 h-9 rounded shrink-0 bg-gray-100 flex items-center justify-center text-gray-400"
    placeholder.innerHTML = `
      <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19V6l12-3v13M9 19a3 3 0 11-6 0 3 3 0 016 0zm12-3a3 3 0 11-6 0 3 3 0 016 0z"/>
      </svg>
    `
    return placeholder
  }

  _syncHiddenInputs() {
    const container = this.hiddenInputsTarget
    container.innerHTML = ""

    if (!this._track) return

    const fields = {
      "planned_post[audio_id]": this._track.audio_id,
      "planned_post[audio_title]": this._track.title,
      "planned_post[audio_artist]": this._track.artist
    }

    Object.entries(fields).forEach(([name, value]) => {
      if (!value) return

      const input = document.createElement("input")
      input.type = "hidden"
      input.name = name
      input.value = value
      container.appendChild(input)
    })
  }
}
