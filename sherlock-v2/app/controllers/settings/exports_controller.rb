class Settings::ExportsController < ApplicationController
  def show
    send_data Current.user.export.to_json, filename: "sherlock-#{Current.user.username}-#{Date.current}.json", type: :json
  end
end
