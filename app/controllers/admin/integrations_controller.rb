class Admin::IntegrationsController < Admin::BaseController
  def update
    integration = Integration.find_by!(slug: params[:slug])
    integration.update!(params.expect(integration: [ :availability ]))
    redirect_to admin_sites_path, notice: "#{integration.name}: #{Admin::SitesController::AVAILABILITY.fetch(integration.availability).downcase}."
  end
end
