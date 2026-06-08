import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["search", "option", "checkbox", "selectedList", "hiddenInputs"]
  static values = { initialIds: { type: Array, default: [] } }

  connect() {
    const validIds = new Set(this.checkboxTargets.map(cb => parseInt(cb.value)))
    this._orderedIds = this.initialIdsValue.filter(id => validIds.has(id))
    // Sync checkbox checked state to match ordered IDs
    this.checkboxTargets.forEach(cb => {
      cb.checked = this._orderedIds.includes(parseInt(cb.value))
    })
    this.render()
  }

  filter() {
    const query = this.searchTarget.value.toLowerCase().trim()
    this.optionTargets.forEach(option => {
      const name = option.querySelector("[data-carousel-select-target='checkbox']").dataset.name.toLowerCase()
      option.classList.toggle("hidden", query.length > 0 && !name.includes(query))
    })
  }

  toggle(event) {
    const id = parseInt(event.currentTarget.value)
    if (event.currentTarget.checked) {
      if (!this._orderedIds.includes(id)) this._orderedIds.push(id)
    } else {
      this._orderedIds = this._orderedIds.filter(i => i !== id)
    }
    this.render()
  }

  render() {
    this._renderSelectedList()
    this._syncHiddenInputs()
  }

  _renderSelectedList() {
    const list = this.selectedListTarget
    list.innerHTML = ""

    if (this._orderedIds.length === 0) return

    this._orderedIds.forEach((id, index) => {
      const checkbox = this.checkboxTargets.find(cb => parseInt(cb.value) === id)
      if (!checkbox) return

      const item = document.createElement("div")
      item.draggable = true
      item.dataset.carouselSelectId = id
      item.dataset.carouselSelectIndex = index
      item.className = "flex items-center gap-2 px-3 py-2 bg-gray-50 border border-gray-200 rounded-lg cursor-grab active:cursor-grabbing select-none"
      item.innerHTML = `
        <span class="text-xs font-medium text-gray-400 w-4 shrink-0">${index + 1}</span>
        <span class="flex-1 text-sm text-gray-700 truncate">${this._escapeHtml(checkbox.dataset.name)}</span>
        <button type="button" data-carousel-select-id="${id}" class="remove-btn p-0.5 rounded text-gray-400 hover:text-red-500 hover:bg-red-50 transition-colors shrink-0" aria-label="Remove">
          <svg class="w-4 h-4 pointer-events-none" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"/>
          </svg>
        </button>
        <svg class="w-4 h-4 text-gray-400 shrink-0 drag-handle" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 8h16M4 16h16"/>
        </svg>
      `

      item.querySelector(".remove-btn").addEventListener("click", this._remove.bind(this))
      item.addEventListener("dragstart", this._dragStart.bind(this))
      item.addEventListener("dragover", this._dragOver.bind(this))
      item.addEventListener("drop", this._dragDrop.bind(this))
      item.addEventListener("dragend", this._dragEnd.bind(this))

      list.appendChild(item)
    })
  }

  _syncHiddenInputs() {
    const container = this.hiddenInputsTarget
    container.innerHTML = ""
    this._orderedIds.forEach(id => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "planned_post[carousel_asset_ids][]"
      input.value = id
      container.appendChild(input)
    })
  }

  _remove(event) {
    const id = parseInt(event.currentTarget.dataset.carouselSelectId)
    this._orderedIds = this._orderedIds.filter(i => i !== id)
    const checkbox = this.checkboxTargets.find(cb => parseInt(cb.value) === id)
    if (checkbox) checkbox.checked = false
    this.render()
  }

  _dragStart(event) {
    this._dragSourceIndex = parseInt(event.currentTarget.dataset.carouselSelectIndex)
    event.currentTarget.classList.add("opacity-50")
    event.dataTransfer.effectAllowed = "move"
  }

  _dragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  _dragDrop(event) {
    event.preventDefault()
    const targetIndex = parseInt(event.currentTarget.dataset.carouselSelectIndex)
    const sourceIndex = this._dragSourceIndex

    if (sourceIndex !== null && sourceIndex !== targetIndex) {
      const [moved] = this._orderedIds.splice(sourceIndex, 1)
      this._orderedIds.splice(targetIndex, 0, moved)
      this._dragSourceIndex = null
      this.render()
    }
  }

  _dragEnd(event) {
    event.currentTarget.classList.remove("opacity-50")
    this._dragSourceIndex = null
  }

  _escapeHtml(str) {
    return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
  }
}
