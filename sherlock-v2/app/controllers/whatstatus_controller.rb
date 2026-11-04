# The old WhatStatus page on the apex whatstatus.info. Static, so no session and no layout.
class WhatstatusController < ApplicationController
  allow_unauthenticated_access

  def show
    render layout: false
  end
end
