import { Controller } from "@hotwired/stimulus"
import { LineChart, AreaChart, SimpleBarChart, HeatmapChart, DonutChart, Ruler, AxisChartsTooltip } from "@carbon/charts"

// Carbon ends a one-point tooltip with a "Group" row. Where that only repeats the title or the
// x axis, the chart sets the group's label to false and the row goes.
const getItems = AxisChartsTooltip.prototype.getItems
AxisChartsTooltip.prototype.getItems = function (event) {
  return getItems.call(this, event).filter((item) => item.label !== false)
}

// Carbon's ruler only shows the tooltip within 5px of a point, so between points most of a line chart
// didn't react. Snap the pointer to the point whose step it's over: lines step after each point, so
// that's the last one at or before it, or the first one left of all of them.
const showRuler = Ruler.prototype.showRuler
Ruler.prototype.showRuler = function (event, [ x, y ]) {
  const scales = this.services.cartesianScales
  const horizontal = scales.getOrientation() === "horizontal"
  const at = horizontal ? y : x
  const values = this.model.getDisplayData().map((datum) => scales.getDomainValue(datum))
  const before = values.filter((value) => value <= at)
  const snapped = before.length ? Math.max(...before) : Math.min(...values)
  return showRuler.call(this, event, horizontal ? [ x, snapped ] : [ snapped, y ])
}

const PALETTE = [ "--accent", "#d08c4a", "#8f7fc4", "#3f9c9a", "#b8a046", "#7890a8" ]
const SAMPLE = " (sample)"
const SAMPLE_STEPS = 60

// Static chart: the server embeds the points as JSON, the controller renders once.
// Types: line, area, bar (over time); column (one bar per label); donut; heatmap.
// Units: "bytes" | "ratio" | "count".
// Step: a bar chart's interval in seconds, so each bar is as wide as the time it covers. Carbon would
// size bars by how many there are, which makes a few hours of data into a few fat bars.
// Mirror: a group drawn below zero, so upload and download bars don't cover each other.
// Sample: { from, since, shape } draws grey placeholder history from the start of the range to the
// first real point, when tracking began inside the range.
export default class extends Controller {
  static targets = [ "canvas", "table" ]
  static values = { points: Array, labels: Object, colors: Object, unit: String, type: { type: String, default: "line" }, filled: Boolean, dots: Boolean, binary: { type: Boolean, default: true }, height: { type: String, default: "260px" }, sample: Object, step: Number, mirror: String, title: String }

  connect() {
    this.#render()
  }

  disconnect() {
    this.chart?.destroy()
    this.layer?.remove()
    this.chart = this.layer = null
  }

  // A page refresh morphs the page into the server's HTML, where the canvas is empty. Keep the drawn
  // chart, and redraw once the new values are in (morphed). A canvas that is going away still goes.
  keepCanvas(event) {
    if (this.hasCanvasTarget && event.target === this.canvasTarget && event.detail.newElement) event.preventDefault()
  }

  keepTableToggle(event) {
    if (this.hasTableTarget && event.target === this.tableTarget && event.detail.attributeName === "hidden") event.preventDefault()
  }

  morphed(event) {
    if (event.target === this.element && this.#key() !== this.renderedKey) this.#render()
  }

  // Draws into a new layer over the old chart and swaps when it's done, so a redraw never flashes empty.
  #render() {
    this.renderedKey = this.#key()
    const old = this.chart
    const oldLayer = this.layer
    this.chart = this.layer = null
    if ((this.pointsValue.length === 0 && !this.sampleValue.shape) || !this.hasCanvasTarget) {
      old?.destroy()
      oldLayer?.remove()
      return
    }
    const layer = document.createElement("div")
    const mount = document.createElement("div")
    layer.append(mount)
    this.samples = this.#samples()
    if (this.samples.length) {
      layer.append(this.#sampleMark())
      layer.dataset.sampleGroups = new Set(this.samples.map((p) => p.group)).size
    }
    if (old) layer.style.cssText = "position: absolute; inset: 0"
    this.canvasTarget.append(layer)
    const [ Chart, options ] = this.#build()
    this.chart = new Chart(mount, {
      data: [ ...this.#data(), ...this.samples ].map((p) => (this.#mirrored(p.group) ? { ...p, value: -p.value } : p)),
      options: {
        height: this.heightValue,
        theme: getComputedStyle(document.documentElement).colorScheme === "dark" ? "g100" : "white",
        animations: false,
        toolbar: { enabled: false },
        ...options,
        // Carbon cuts tooltip text past 16 characters, which hides most of "15.6 MiB (16,357,212 bytes)".
        tooltip: { ...options.tooltip, truncation: { type: "none" } }
      }
    })
    this.layer = layer
    if (!old) return
    let swapped = false
    const swap = () => {
      if (swapped) return
      swapped = true
      old.destroy()
      oldLayer.remove()
      layer.style.cssText = ""
    }
    this.chart.services.events.addEventListener("render-finished", swap, { once: true })
    setTimeout(swap, 1000)
  }

  // Everything the server sends that changes the drawing.
  #key() {
    return [ "points", "labels", "colors", "unit", "type", "filled", "dots", "binary", "height", "sample", "step", "mirror", "title" ].map((name) => this.element.getAttribute(`data-chart-${name}-value`)).join("|")
  }

  toggleTable() {
    this.tableTarget.hidden = !this.tableTarget.hidden
    this.canvasTarget.hidden = !this.tableTarget.hidden
  }

  #data() {
    if (this.pointsValue[0]?.date === undefined) return this.pointsValue
    return this.pointsValue.map((p) => ({ ...p, date: new Date(p.date) }))
  }

  #build() {
    const groups = [ ...new Set(this.pointsValue.map((p) => p.group)) ]
    const style = getComputedStyle(document.documentElement)
    const palette = PALETTE.map((c) => (c.startsWith("--") ? style.getPropertyValue(c).trim() : c))
    const grey = style.getPropertyValue("--line-strong").trim()
    const samples = [ ...new Set(this.samples.map((p) => p.group)) ]
    // Groups a tracker names carry its own color; the rest fall back to the palette.
    const custom = this.colorsValue || {}
    const colors = { scale: Object.fromEntries([ ...groups.map((g, i) => [ g, custom[g] || palette[i % palette.length] ]), ...samples.map((g) => [ g, grey ]) ]) }
    // Tooltips pass every cell through here, labels and tracker names too, so only numbers are formatted.
    const tooltip = { valueFormatter: (v) => (v instanceof Date ? this.#date(v) : typeof v === "number" ? this.#format(this.mirrorValue ? Math.abs(v) : v, true) : v) }

    switch (this.typeValue) {
      case "heatmap":
        return [ HeatmapChart, {
          axes: {
            // Titles name the axes in the tooltip; the CSS hides them on the chart itself.
            bottom: { mapsTo: "x", scaleType: "labels", domain: this.labelsValue.x, title: this.labelsValue.x_title, ticks: { values: this.#sparseLabels(), rotation: "never" } },
            // Carbon draws the first label at the bottom; we want Monday on top.
            left: { mapsTo: "y", scaleType: "labels", domain: [ ...this.labelsValue.y ].reverse(), title: this.labelsValue.y_title }
          },
          heatmap: { colorLegend: { title: "Uploaded" }, divider: { state: "on" } },
          locale: { number: (v) => this.#format(v), translations: { total: "Uploaded" } },
          color: { gradient: { colors: this.#gradient() } },
          tooltip
        } ]
      case "column":
        return [ SimpleBarChart, {
          legend: { enabled: false },
          color: { scale: Object.fromEntries(groups.map((g) => [ g, palette[0] ])) },
          grid: { x: { enabled: false } },
          axes: {
            // Titles name the axes in the tooltip, where the x axis already names the bar.
            bottom: { mapsTo: "group", scaleType: "labels", title: this.labelsValue.x_title },
            left: { mapsTo: "value", title: this.labelsValue.y_title, ticks: { formatter: (v) => this.#format(v) } }
          },
          locale: { translations: { group: false } },
          tooltip: { ...tooltip, groupLabel: false }
        } ]
      case "donut":
        return [ DonutChart, {
          color: colors,
          legend: { alignment: "center" },
          donut: { alignment: "center", center: { label: "Uploaded", numberFormatter: (v) => this.#format(v) } },
          tooltip
        } ]
      default: {
        const group = groups.length + samples.length > 1 && (Object.keys(custom).length ? "Tracker" : "Group")
        const type = this.typeValue === "line" && this.filledValue && groups.length === 1 && !this.samples.length ? AreaChart : this.typeValue === "bar" ? SimpleBarChart : LineChart
        return [ type, {
          legend: { enabled: groups.length > 1, alignment: "left" },
          color: colors,
          // Stats only change when a poll comes in, so the value holds until the next one.
          curve: "curveStepAfter",
          // A lone real point has no line to draw, so it gets a dot. Placeholder lines never do.
          points: { enabled: this.dotsValue || this.#lonePoint(), filled: this.samples.length > 0 || undefined, radius: 2 },
          ...(this.stepValue && { bars: { width: this.#barWidth(), maxWidth: 16 } }),
          ...(this.typeValue !== "bar" && {
            getStrokeColor: (group, label, datum) => (this.#placeholderDot(group, datum) ? "transparent" : colors.scale[group]),
            getFillColor: (group, label, datum) => (this.#placeholderDot(group, datum) ? "transparent" : colors.scale[group])
          }),
          grid: { x: { enabled: false } },
          // Carbon rounds the time axis out to whole ticks by default, which leaves empty days on both
          // sides. The axis spans the data, so the newest point is at the right edge.
          timeScale: { addSpaceOnEdges: 0 },
          axes: {
            // The title names the axis in the tooltip; the CSS hides it on the chart itself.
            bottom: { mapsTo: "date", scaleType: "time", title: "Time", domain: this.#barDomain(), thresholds: this.#trackingStart(), ticks: { number: this.#tickCount(), formatter: (d) => this.#tick(d) } },
            // Placeholder bars without any real ones have no scale worth labelling.
            left: { mapsTo: "value", title: this.titleValue, includeZero: this.unitValue !== "ratio", ticks: { formatter: (v) => (this.#scaleless() || this.#fractionalCount(v) ? "" : this.#format(this.mirrorValue ? Math.abs(v) : v)) } }
          },
          // A lone group is the chart's title already. Totals would add up ratios, or subtract the mirrored
          // download from the upload.
          locale: { translations: { group } },
          tooltip: { ...tooltip, groupLabel: group, showTotal: false }
        } ]
      }
    }
  }

  // Placeholder points from the start of the range to the first real point, per group. A line's last
  // placeholder sits on its first real point so the two join. Seeded by the tracking start, so the
  // shape stays the same across reloads.
  #samples() {
    const { from, since, shape } = this.sampleValue
    if (!shape) return []
    const real = this.#data()
    const start = new Date(from).getTime()
    const end = real.length ? Math.min(...real.map((p) => p.date.getTime())) : new Date(since).getTime()
    const groups = real.length ? [ ...new Set(real.map((p) => p.group)) ] : [ "Placeholder" ]
    this.sampleEnd = new Date(end)
    // Placeholder bars come one per interval, like the real ones.
    const steps = this.stepValue ? Math.min(500, Math.max(1, Math.round((end - start) / (this.stepValue * 1000)))) : SAMPLE_STEPS
    return groups.flatMap((group) => {
      const values = real.filter((p) => p.group === group).map((p) => p.value)
      const walk = this.#walk(shape, values, this.#random(`${since}|${group}`), steps)
      return walk.map((value, i) => ({
        group: group + SAMPLE,
        date: new Date(start + ((end - start) * i) / steps),
        value: this.unitValue === "count" ? Math.round(value) : value
      }))
    })
  }

  // Works backwards from the first real value: totals only shrink into the past, levels wander with
  // a gentle upward trend, intervals scatter around the real average.
  #walk(shape, values, random, steps) {
    if (shape === "interval") {
      const typical = values.length ? values.reduce((a, b) => a + b, 0) / values.length : 0
      const base = typical > 0 ? typical : 1
      return Array.from({ length: steps }, () => (random() < 0.1 ? 0 : base * Math.exp((random() - 0.5) * 1.2)))
    }
    const anchor = values[0] ?? 0
    const scale = Math.abs(anchor) || 1
    const walk = [ anchor ]
    let value = anchor
    for (let i = 0; i < steps; i++) {
      value = shape === "total"
        ? value - (random() < 0.3 ? 0 : random() * scale * 0.008)
        : value - scale * 0.003 + (random() - 0.5) * scale * 0.035
      if (anchor >= 0) value = Math.max(0, value)
      walk.unshift(value)
    }
    return walk
  }

  // mulberry32, seeded from a string.
  #random(seed) {
    let a = [ ...seed ].reduce((h, c) => Math.imul(h ^ c.charCodeAt(0), 2654435761), 1779033703) >>> 0
    return () => {
      a = (a + 0x6d2b79f5) | 0
      let t = Math.imul(a ^ (a >>> 15), 1 | a)
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296
    }
  }

  #mirrored(group) {
    return this.mirrorValue && (group === this.mirrorValue || group === this.mirrorValue + SAMPLE)
  }

  #lonePoint() {
    const counts = {}
    this.pointsValue.forEach((p) => { counts[p.group] = (counts[p.group] || 0) + 1 })
    return Object.values(counts).includes(1)
  }

  // Carbon asks for about seven time ticks however narrow the chart is, and writes the first one in
  // full ("Oct 24, 10:45 AM"), so labels ran into each other. One tick per 80px, and short labels.
  #tickCount() {
    return Math.max(2, Math.floor((this.canvasTarget.clientWidth - 70) / 80))
  }

  // A year on Jan 1, a date at midnight, otherwise the time, in 24 hours like the rest of Sherlock.
  #tick(date) {
    // Daily data has nothing to say about hours, so those ticks stay blank.
    if (this.stepValue >= 86400 && (date.getHours() || date.getMinutes())) return ""
    if (date.getHours() || date.getMinutes()) return date.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" })
    if (date.getMonth() === 0 && date.getDate() === 1) return String(date.getFullYear())
    return date.toLocaleDateString("en", { month: "short", day: "numeric" })
  }

  // A whole date for tooltips: "Sat, Oct 25, 02:00".
  #date(date) {
    return date.toLocaleDateString("en", { weekday: "short", month: "short", day: "numeric" }) + ", "
      + date.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" })
  }

  // Bars fill most of their interval across the plot, which is the canvas less the value axis.
  // Bars are centred on their time, and the axis ends at the first and last one, so they'd stick half
  // out of the chart. Half a step more on each side keeps them inside. Lines keep the plain data span.
  #barDomain() {
    if (this.typeValue !== "bar" || !this.stepValue) return undefined
    const times = [ ...this.#data(), ...this.samples ].map((p) => p.date.getTime())
    const half = (this.stepValue * 1000) / 2
    return [ new Date(Math.min(...times) - half), new Date(Math.max(...times) + half) ]
  }

  #barWidth() {
    const times = [ ...this.#data(), ...this.samples ].map((p) => p.date.getTime())
    const step = this.stepValue * 1000
    const span = Math.max(...times) - Math.min(...times) + step
    return Math.min(16, Math.max(1, ((this.canvasTarget.clientWidth - 70) * step * 0.7) / span))
  }

  // Lines pass all their points to the color callbacks, dots pass one.
  #placeholderDot(group, datum) {
    return group.endsWith(SAMPLE) && datum && !Array.isArray(datum)
  }

  #scaleless() {
    return this.samples.length > 0 && this.sampleValue.shape === "interval" && !this.pointsValue.some((p) => p.value > 0)
  }

  #trackingStart() {
    if (!this.samples.length) return []
    return [ { value: this.sampleEnd, label: "Tracking since", valueFormatter: (d) => this.#date(new Date(d)), fillColor: getComputedStyle(document.documentElement).getPropertyValue("--muted").trim() } ]
  }

  // A faint "Sample" across the placeholder part of the chart.
  #sampleMark() {
    const mark = document.createElement("span")
    mark.className = "chart-sample-mark"
    mark.setAttribute("aria-hidden", "true")
    mark.textContent = "Sample"
    const start = this.samples[0].date.getTime()
    const end = this.sampleEnd.getTime()
    mark.style.width = `${Math.min(100, (100 * (end - start)) / (Date.now() - start))}%`
    return mark
  }

  // Five steps from --accent-soft to --accent, so heatmaps follow the theme.
  #gradient() {
    const style = getComputedStyle(document.documentElement)
    const from = this.#rgb(style.getPropertyValue("--accent-soft"))
    const to = this.#rgb(style.getPropertyValue("--accent"))
    return [ 0, 0.25, 0.5, 0.75, 1 ].map((t) => "#" + from.map((c, i) => Math.round(c + (to[i] - c) * t).toString(16).padStart(2, "0")).join(""))
  }

  #rgb(hex) {
    const h = hex.trim().replace("#", "")
    return [ 0, 2, 4 ].map((i) => parseInt(h.slice(i, i + 2), 16))
  }

  // Long label axes (24 hours, 26 weeks) would overlap, so only every few labels are drawn.
  // Carbon ignores tick formatters on label axes, so pass the labels to draw as tick values.
  #sparseLabels() {
    const labels = this.labelsValue.x || []
    const step = Math.ceil(labels.length / Math.min(12, this.#tickCount()))
    return labels.filter((_, i) => i % step === 0)
  }

  // Small counts get ticks like 0.5, which would round to the label of the tick beside them.
  #fractionalCount(value) {
    return this.unitValue === "count" && !Number.isInteger(value)
  }

  #format(value, exact = false) {
    if (value === null || value === undefined) return "—"
    if (this.unitValue === "ratio") return Number(value).toFixed(2)
    // Bonus points come with cents; whole points read better, as in the table.
    if (this.unitValue === "count") return Math.round(value).toLocaleString()
    const base = this.binaryValue ? 1024 : 1000
    const units = this.binaryValue ? [ "B", "KiB", "MiB", "GiB", "TiB", "PiB" ] : [ "B", "KB", "MB", "GB", "TB", "PB" ]
    let size = Math.abs(value), i = 0
    while (size >= base && i < units.length - 1) { size /= base; i++ }
    const text = `${value < 0 ? "−" : ""}${size.toFixed(size < 10 && i > 0 ? 2 : 1).replace(/\.0+$/, "")} ${units[i]}`
    return exact ? `${text} (${this.#rounded(value).toLocaleString()} bytes)` : text
  }

  // The exact count in the tooltip is for reference, so four digits carry it: 9,157,437,012,292
  // bytes reads as 9,157,000,000,000.
  #rounded(value) {
    return Number(Math.round(value).toPrecision(4))
  }
}
