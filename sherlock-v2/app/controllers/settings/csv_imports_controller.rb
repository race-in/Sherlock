class Settings::CsvImportsController < ApplicationController
  MAX_SIZE = 50.megabytes

  rate_limit to: 5, within: 1.minute, with: -> { done(alert: "Too many imports. Wait a minute and try again.") }

  def create
    file = params[:file]
    return done(alert: "Choose a CSV file first.") unless file.respond_to?(:read)
    return done(alert: "That file is larger than 50 MB.") if file.size > MAX_SIZE

    connection = Current.user.connections.find_by(id: params[:connection_id])
    return done(alert: "Choose one of your own trackers.") unless connection

    added = StatisticsCsvImporter.import!(connection:, user: Current.user, csv_text: file.read)
    done(notice: "Imported #{helpers.pluralize(added, "statistics point")}. Existing timestamps were skipped.")
  rescue ArgumentError => error
    done(alert: error.message)
  end

  private
    def done(notice: nil, alert: nil)
      redirect_to settings_data_path(anchor: "csv-import"), flash: { csv_import_notice: notice, csv_import_alert: alert }.compact
    end
end
