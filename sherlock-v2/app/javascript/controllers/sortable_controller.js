import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Reorders its items while editing: drag a handle with a mouse or a finger, or use the arrow keys on
// it. Each change sends the ids in their new order to url as ids[] right away. Done refreshes the page,
// which morphs, so the sidebar follows. Refreshing after every drop would end editing, since the
// editing state only lives here.
export default class extends Controller {
  static targets = [ "item" ]
  static values = { url: String }

  edit() {
    this.element.dataset.editing = ""
    this.itemTargets[0]?.querySelector("button")?.focus()
  }

  async done() {
    await this.saving
    delete this.element.dataset.editing
    if (this.changed) Turbo.visit(window.location.href, { action: "replace" })
    this.changed = false
  }

  grab(event) {
    if (event.button !== 0) return
    event.preventDefault()
    event.currentTarget.setPointerCapture(event.pointerId)
    this.dragged = this.#itemOf(event.currentTarget)
    this.before = this.#ids()
    this.dragged.classList.add("sortable-dragging")
  }

  drag(event) {
    if (!this.dragged) return
    const over = this.itemTargets.find((item) => {
      const { top, bottom } = item.getBoundingClientRect()
      return item !== this.dragged && event.clientY >= top && event.clientY <= bottom
    })
    if (!over) return
    const { top, height } = over.getBoundingClientRect()
    this.#move(() => over[event.clientY < top + height / 2 ? "before" : "after"](this.dragged))
  }

  drop() {
    if (!this.dragged) return
    this.dragged.classList.remove("sortable-dragging")
    this.dragged = null
    if (this.#ids().join() !== this.before.join()) this.#save()
  }

  key(event) {
    const item = this.#itemOf(event.currentTarget)
    if (event.key === "ArrowUp" && item.previousElementSibling) this.#move(() => item.previousElementSibling.before(item))
    else if (event.key === "ArrowDown" && item.nextElementSibling) this.#move(() => item.nextElementSibling.after(item))
    else return
    event.preventDefault()
    event.currentTarget.focus()
    this.#save()
  }

  #itemOf(element) {
    return this.itemTargets.find((item) => item.contains(element))
  }

  // Moves rows, then slides each one from where it was to where it is now.
  #move(change) {
    const before = new Map(this.itemTargets.map((item) => [ item, item.getBoundingClientRect().top ]))
    change()
    for (const item of this.itemTargets) {
      const shift = before.get(item) - item.getBoundingClientRect().top
      if (shift && item !== this.dragged) item.animate([ { transform: `translateY(${shift}px)` }, { transform: "none" } ], { duration: 150, easing: "ease-out" })
    }
  }

  #ids() {
    return this.itemTargets.map((item) => item.dataset.id)
  }

  #save() {
    const body = new FormData()
    this.#ids().forEach((id) => body.append("ids[]", id))
    this.changed = true
    this.saving = fetch(this.urlValue, {
      method: "PATCH",
      body,
      headers: { "X-CSRF-Token": document.querySelector("meta[name=csrf-token]").content }
    })
  }
}
