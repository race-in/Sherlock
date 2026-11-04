import "@carbon/charts/styles.css"
import "./styles/carbon_charts.css"
import { Application } from "@hotwired/stimulus"
import ChartController from "./charts/chart_controller"

// Carbon and d3 are large, so chart pages load this bundle with their own Stimulus app.
// The controller lives outside controllers/, so stimulus:manifest:update never registers it in
// application.js too: a second registration draws every chart twice.
const application = Application.start()
application.register("chart", ChartController)
