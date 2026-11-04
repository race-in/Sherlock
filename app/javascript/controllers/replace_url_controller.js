import { Controller } from "@hotwired/stimulus"

// Swaps the address bar to a GET page after a rendered POST, so reloading doesn't send the form again.
export default class extends Controller {
  static values = { url: String }

  connect() {
    history.replaceState(history.state, "", this.urlValue)
  }
}
