import { Controller } from "@hotwired/stimulus"

// Chip input for Instagram collaborators.
//
// Instagram has no username search API, so the dropdown suggests usernames the
// account has collaborated with before (served by PlannedPosts#collaborator_search).
// Anything typed can be added regardless of whether it appears in the list.
export default class extends Controller {
  static targets = ["chips", "input", "suggestions", "hiddenInputs", "counter"]
  static values = {
    url: String,
    max: { type: Number, default: 3 },
    initial: { type: Array, default: [] },
    delay: { type: Number, default: 250 }
  }

  connect() {
    this._selected = [...this.initialValue]
    this._timer = null
    this.render()
  }

  disconnect() {
    clearTimeout(this._timer)
  }

  // ---------------------------------------------------------------------
  // Suggestions
  // ---------------------------------------------------------------------

  search() {
    clearTimeout(this._timer)
    this._timer = setTimeout(() => this._fetchSuggestions(), this.delayValue)
  }

  async _fetchSuggestions() {
    if (this.isFull) {
      this._renderSuggestions([])
      return
    }

    const query = this.query
    const url = `${this.urlValue}?q=${encodeURIComponent(query)}`

    try {
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) throw new Error(response.statusText)

      const data = await response.json()
      this._renderSuggestions(data.collaborators || [])
    } catch {
      // History is a convenience, not a requirement — a failed lookup still
      // leaves free-text entry working.
      this._renderSuggestions([])
    }
  }

  hideSuggestions() {
    // Delayed so a mousedown on a suggestion is processed before the blur.
    setTimeout(() => this.suggestionsTarget.classList.add("hidden"), 120)
  }

  // ---------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------

  keydown(event) {
    if (event.key === "Enter" || event.key === ",") {
      event.preventDefault()
      this.addUsername(this.query)
    } else if (event.key === "Backspace" && this.query === "" && this._selected.length > 0) {
      this._selected.pop()
      this.render()
    } else if (event.key === "Escape") {
      this.suggestionsTarget.classList.add("hidden")
    }
  }

  addUsername(raw) {
    const username = this._normalize(raw)
    if (username === "") return

    if (this.isFull) {
      this._flashCounter()
      return
    }

    if (!this._selected.includes(username)) this._selected.push(username)

    this.inputTarget.value = ""
    this.suggestionsTarget.classList.add("hidden")
    this.render()
  }

  removeUsername(username) {
    this._selected = this._selected.filter(name => name !== username)
    this.render()
  }

  // ---------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------

  render() {
    this._renderChips()
    this._syncHiddenInputs()

    this.counterTarget.textContent = `${this._selected.length} of ${this.maxValue}`
    this.inputTarget.disabled = this.isFull
    this.inputTarget.placeholder = this.isFull
      ? `Maximum ${this.maxValue} collaborators`
      : "Search or type a username…"
  }

  _renderChips() {
    this.chipsTarget.innerHTML = ""

    this._selected.forEach(username => {
      const chip = document.createElement("span")
      chip.className =
        "inline-flex items-center gap-1 pl-2 pr-1 py-0.5 bg-indigo-50 text-indigo-700 text-sm rounded-md"

      const label = document.createElement("span")
      label.textContent = `@${username}`
      chip.appendChild(label)

      const remove = document.createElement("button")
      remove.type = "button"
      remove.className = "p-0.5 rounded hover:bg-indigo-100 transition-colors"
      remove.setAttribute("aria-label", `Remove ${username}`)
      remove.innerHTML = `
        <svg class="w-3.5 h-3.5 pointer-events-none" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
        </svg>
      `
      remove.addEventListener("click", () => this.removeUsername(username))
      chip.appendChild(remove)

      this.chipsTarget.appendChild(chip)
    })
  }

  _renderSuggestions(collaborators) {
    const list = this.suggestionsTarget
    list.innerHTML = ""

    const query = this._normalize(this.query)
    const unused = collaborators.filter(entry => !this._selected.includes(entry.username))

    unused.forEach(entry => {
      list.appendChild(
        this._suggestionRow(entry.username, `used ${entry.count}×`)
      )
    })

    // Free-text escape hatch: offer whatever was typed when it is not already
    // an exact suggestion or an existing chip.
    const isNew =
      query !== "" &&
      !this._selected.includes(query) &&
      !unused.some(entry => entry.username === query)

    if (isNew) list.appendChild(this._suggestionRow(query, "add new", true))

    list.classList.toggle("hidden", list.childElementCount === 0)
  }

  _suggestionRow(username, note, isNew = false) {
    const row = document.createElement("button")
    row.type = "button"
    row.className =
      "w-full flex items-center justify-between gap-2 px-3 py-2 text-left hover:bg-gray-50 transition-colors"

    const name = document.createElement("span")
    name.className = "text-sm text-gray-700 truncate"
    name.textContent = isNew ? `Add "@${username}"` : `@${username}`

    const meta = document.createElement("span")
    meta.className = "text-xs text-gray-400 shrink-0"
    meta.textContent = note

    row.append(name, meta)

    // mousedown, not click: the input's blur would otherwise hide the list first.
    row.addEventListener("mousedown", event => {
      event.preventDefault()
      this.addUsername(username)
    })

    return row
  }

  _syncHiddenInputs() {
    this.hiddenInputsTarget.innerHTML = ""

    this._selected.forEach(username => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "planned_post[collaborators][]"
      input.value = username
      this.hiddenInputsTarget.appendChild(input)
    })
  }

  _flashCounter() {
    this.counterTarget.classList.add("text-red-500")
    setTimeout(() => this.counterTarget.classList.remove("text-red-500"), 800)
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  get query() {
    return this.inputTarget.value.trim()
  }

  get isFull() {
    return this._selected.length >= this.maxValue
  }

  _normalize(value) {
    return value.trim().replace(/^@/, "").replace(/,/g, "")
  }
}
