import { Controller } from "@hotwired/stimulus"

// Shows what's typed in a field somewhere else on the page, like the contact inside the User-Agent
// preview. Shows the fallback while the field is empty.
export default class extends Controller {
  static targets = [ "source", "output" ]
  static values = { fallback: String }

  connect() {
    this.update()
  }

  update() {
    this.outputTarget.textContent = this.sourceTarget.value.trim() || this.fallbackValue
  }
}
