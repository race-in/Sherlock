class Admin::Sites::BaseController < Admin::BaseController
  before_action :set_site

  private
    def set_site
      @site = Site.where.not(tier: :unsupported).find_by!(slug: params[:site_slug])
    end
end
