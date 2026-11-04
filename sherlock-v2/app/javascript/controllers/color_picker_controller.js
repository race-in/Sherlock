import { Controller } from "@hotwired/stimulus"
import { HexColorPicker } from "vanilla-colorful"

// A hex-color-picker next to a text field: moving either keeps the other and the swatch in step.
// Naming HexColorPicker keeps esbuild from dropping the import that registers the element.
void HexColorPicker

export default class extends Controller {
  static targets = [ "picker", "field", "swatch" ]

  pick(event) {
    this.fieldTarget.value = event.detail.value
    this.swatchTarget.style.background = event.detail.value
  }

  type() {
    const color = this.fieldTarget.value.trim().toLowerCase()
    if (!/^#[0-9a-f]{6}$/.test(color)) return
    this.pickerTarget.setAttribute("color", color)
    this.swatchTarget.style.background = color
  }
}
