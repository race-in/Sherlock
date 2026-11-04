import { Controller } from "@hotwired/stimulus"

// Fills a field with the browser's time zone, unless the user already picked one.
export default class extends Controller {
  static targets = [ "field" ]
  static values = { overwrite: { type: Boolean, default: true } }

  connect() {
    const zone = Intl.DateTimeFormat().resolvedOptions().timeZone
    if (!zone) return

    this.fieldTargets.forEach((field) => {
      if (!this.overwriteValue) return
      const exists = field.tagName !== "SELECT" || [ ...field.options ].some((option) => option.value === zone)
      if (exists) field.value = zone
    })
  }
}
