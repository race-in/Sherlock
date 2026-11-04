class Admin::Sites::PausesController < Admin::Sites::BaseController
  def create
    @site.pause!(:admin)
    redirect_back_or_to admin_site_path(@site), notice: "Paused #{@site.name}. Sherlock sends it nothing until you resume."
  end

  def destroy
    @site.resume!
    redirect_back_or_to admin_site_path(@site), notice: "Resumed #{@site.name}.", status: :see_other
  end
end
