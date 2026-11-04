import { Controller } from "@hotwired/stimulus"

// Closes a <details> popover on a click outside it or on Escape.
export default class extends Controller {
  closeOutside(event) {
    if (this.element.open && !this.element.contains(event.target)) this.element.open = false
  }

  close() {
    this.element.open = false
  }
}
