import { Controller } from "@hotwired/stimulus"

// Hides items whose data-name doesn't contain the query, and groups left with no item showing.
export default class extends Controller {
  static targets = [ "query", "item", "group" ]

  apply() {
    const query = this.queryTarget.value.trim().toLowerCase()
    this.itemTargets.forEach((item) => { item.hidden = !item.dataset.name.includes(query) })
    this.groupTargets.forEach((group) => {
      group.hidden = !this.itemTargets.some((item) => group.contains(item) && !item.hidden)
    })
  }
}
