# Where an opt-in link on a tracker profile leads. The page is the same for every code, so it says
# nothing about who put the link there or whether they're on Sherlock.
class OptInsController < ApplicationController
  allow_unauthenticated_access
  layout "public"

  def show
  end
end
