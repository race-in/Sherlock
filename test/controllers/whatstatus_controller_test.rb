require "test_helper"

class WhatstatusControllerTest < ActionDispatch::IntegrationTest
  test "the apex host gets the old WhatStatus page, the app host gets Sherlock" do
    host! "whatstatus.info"
    get root_path
    assert_response :success
    assert_includes response.body, "WhatStatus.info"
    assert_includes response.body, "/session/new"
    assert_not_includes response.body, "#{Rails.configuration.x.source_url}/releases/tag/"

    host! "app.whatstatus.info"
    get root_path
    assert_not_includes response.body, "WhatStatus.info"
    follow_redirect! while response.redirect?
    assert_includes response.body, "#{Rails.configuration.x.source_url}/releases/tag/#{Rails.configuration.x.version}"
  end
end
