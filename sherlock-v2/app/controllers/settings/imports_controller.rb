# The result shows in the Import card on the data page, where it stays, rather than as a toast that is easy
# to miss after picking a file.
class Settings::ImportsController < ApplicationController
  MAX_SIZE = 50.megabytes

  rate_limit to: 5, within: 1.minute, with: -> { done(alert: "Too many imports. Wait a minute and try again.") }

  def create
    file = params[:file]
    return done(alert: "Choose an export file first.") unless file.respond_to?(:read)
    return done(alert: "That file is larger than 50 MB.") if file.size > MAX_SIZE

    added, missing = Current.user.import!(file.read)
    notice = "Imported #{helpers.pluralize(added, "update")}."
    notice += " Add #{missing.to_sentence} first, then import the same file again." if missing.any?
    done(notice:)
  rescue ArgumentError => error
    done(alert: error.message)
  end

  private
    def done(notice: nil, alert: nil)
      redirect_to settings_data_path(anchor: "import"), flash: { import_notice: notice, import_alert: alert }.compact
    end
end
