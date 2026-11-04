import { Controller } from "@hotwired/stimulus"

const ICONS = { notice: "bi-check-circle", alert: "bi-exclamation-triangle" }

// Flash messages, and window.dispatchEvent(new CustomEvent("toast:show", { detail: { message, kind } })).
export default class extends Controller {
  static targets = [ "container" ]
  static values = { flashes: Object, duration: { type: Number, default: 5000 } }

  connect() {
    Object.entries(this.flashesValue).forEach(([ kind, message ]) => this.#render(message, kind))
  }

  receive({ detail: { message, kind } = {} }) {
    if (message) this.#render(message, kind)
  }

  #render(message, kind = "notice") {
    const toast = document.createElement("li")
    toast.className = "pointer-events-auto flex max-w-sm items-start gap-2 rounded-lg bg-ink px-4 py-3 text-sm text-canvas shadow-lg transition-opacity duration-200"
    toast.setAttribute("role", kind === "alert" ? "alert" : "status")

    const icon = document.createElement("i")
    icon.className = `bi ${ICONS[kind] || ICONS.notice} mt-px`
    const text = document.createElement("span")
    text.textContent = message
    toast.append(icon, text)

    this.containerTarget.appendChild(toast)
    setTimeout(() => this.#dismiss(toast), kind === "alert" ? this.durationValue * 2 : this.durationValue)
  }

  #dismiss(toast) {
    toast.classList.add("opacity-0")
    setTimeout(() => toast.remove(), 200)
  }
}
