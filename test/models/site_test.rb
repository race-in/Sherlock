require "test_helper"

class SiteTest < ActiveSupport::TestCase
  test "every site has a default color that looks like one" do
    Site.find_each do |site|
      assert_match(/\A#[0-9a-f]{6}\z/, site.default_color, site.slug)
    end
  end

  test "the named trackers start with a color near their icon" do
    assert_equal "#8e90c8", sites(:redacted).default_color
    assert_equal "#2a9bc9", sites(:broadcasthenet).default_color
  end
end
