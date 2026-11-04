class Settings::QuiConnectionsController < ApplicationController
  before_action { head :not_found unless Integration.qui.available_to?(Current.user) }
  rate_limit to: 10, within: 1.minute, only: %i[create poll], with: -> { redirect_to settings_qui_connections_path, alert: "Too many tests. Wait a minute and try again." }

  def index
    @quis = Current.user.qui_connections.order(:id)
  end

  def create
    qui = QuiConnection.connect!(user: Current.user, **params.expect(qui: [ :url, :api_key, :label ]).to_h.symbolize_keys)
    redirect_to settings_qui_connections_path, notice: "#{qui.name} answered. Cross-seeds updated."
  rescue Engines::Error, ActiveRecord::RecordInvalid => error
    @quis = Current.user.qui_connections.order(:id)
    @url = params.dig(:qui, :url)
    @error = error.is_a?(ActiveRecord::RecordInvalid) ? error.record.errors.full_messages.to_sentence : error.message
    render :index, status: :unprocessable_entity
  end

  def update
    qui = Current.user.qui_connections.find(params[:id])
    if qui.update(params.expect(qui: [ :label ]))
      redirect_to settings_qui_connections_path, notice: "Renamed to #{qui.name}."
    else
      redirect_to settings_qui_connections_path, alert: qui.errors.full_messages.to_sentence
    end
  end

  def poll
    if QuiConnection.poll!(Current.user)
      redirect_to settings_qui_connections_path, notice: "qui answered. Cross-seeds updated."
    else
      redirect_to settings_qui_connections_path, alert: "Not every qui answered, so cross-seeds weren't updated."
    end
  end

  def destroy
    qui = Current.user.qui_connections.find(params[:id])
    qui.destroy!
    redirect_to settings_qui_connections_path, notice: "Removed #{qui.name}. The cross-seed history on your trackers stays.", status: :see_other
  end
end
