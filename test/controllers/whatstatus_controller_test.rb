require "test_helper"

class WhatstatusControllerTest < ActionDispatch::IntegrationTest
  # The footer only links a release when the app knows its version, which needs a git tag or APP_VERSION.
  # A fresh checkout (like CI's) has neither, so the test sets one.
  setup do
    @original_version = Rails.configuration.x.version
    Rails.configuration.x.version = "v1.2.3"
  end

  teardown { Rails.configuration.x.version = @original_version }

  test "the apex host gets the old WhatStatus page, the app host gets Sherlock" do
    release_path = "#{Rails.configuration.x.source_url}/releases/tag/"

    host! "whatstatus.info"
    get root_path
    assert_response :success
    assert_includes response.body, "WhatStatus.info"
    assert_includes response.body, "/session/new"
    assert_not_includes response.body, release_path

    host! "app.whatstatus.info"
    get root_path
    assert_not_includes response.body, "WhatStatus.info"
    follow_redirect! while response.redirect?
    assert_includes response.body, "#{release_path}#{Rails.configuration.x.version}"
  end
end
