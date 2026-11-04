import { Controller } from "@hotwired/stimulus"

// Scrolls to the top when the element appears. Redirects back to the same page are Turbo refreshes,
// which keep the scroll position, so news shown at the top would otherwise stay out of sight.
export default class extends Controller {
  connect() {
    window.scrollTo({ top: 0, behavior: "smooth" })
  }
}
