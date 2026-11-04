import { Controller } from "@hotwired/stimulus"

// A tracker test or a profile check takes a few seconds; say so instead of looking stuck.
export default class extends Controller {
  static targets = [ "button", "label", "spinner" ]
  static values = { label: { type: String, default: "Testing…" } }

  connect() {
    this.element.addEventListener("turbo:submit-start", () => {
      this.buttonTarget.disabled = true
      this.labelTarget.textContent = this.labelValue
      if (this.hasSpinnerTarget) this.spinnerTarget.hidden = false
    })
  }
}
