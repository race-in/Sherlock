import { Controller } from "@hotwired/stimulus"

// The navigation drawer on small screens. A Turbo visit renders a new body, which closes it.
export default class extends Controller {
  static targets = [ "button", "panel" ]

  toggle() {
    this.#set(this.panelTarget.classList.contains("hidden"))
  }

  close() {
    this.#set(false)
  }

  #set(open) {
    this.panelTarget.classList.toggle("hidden", !open)
    this.panelTarget.classList.toggle("flex", open)
    this.buttonTarget.setAttribute("aria-expanded", open)
    this.buttonTarget.querySelector("i").className = open ? "bi bi-x-lg" : "bi bi-list"
    document.documentElement.classList.toggle("overflow-hidden", open)
  }
}
