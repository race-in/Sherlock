require "csv"
require "tempfile"
require "test_helper"

class Settings::CsvImportsControllerTest < ActionDispatch::IntegrationTest
  test "imports a CSV file into the selected owned tracker" do
    sign_in_as users(:alice)
    connection = connections(:alice_redacted)
    observed_at = 5.days.ago.change(usec: 0)
    csv = CSV.generate do |writer|
      writer << %w[time uploaded downloaded]
      writer << [ observed_at.iso8601, "987654321", "123456789" ]
    end
    Tempfile.create([ "history", ".csv" ]) do |tempfile|
      tempfile.write(csv)
      tempfile.rewind
      upload = Rack::Test::UploadedFile.new(tempfile.path, "text/csv", original_filename: "history.csv")

      assert_difference -> { connection.snapshots.count }, 1 do
        post settings_csv_import_path, params: { connection_id: connection.id, file: upload }
      end
    end

    snapshot = connection.snapshots.find_by!(created_at: observed_at)
    assert_equal "csv_import", snapshot.source
    assert_equal users(:alice), snapshot.created_by_user
    assert_redirected_to settings_data_path(anchor: "csv-import")
  end

  test "a member cannot import into another member's tracker" do
    sign_in_as users(:bob)
    connection = connections(:alice_redacted)
    csv = CSV.generate do |writer|
      writer << %w[time uploaded downloaded]
      writer << [ 5.days.ago.iso8601, "1", "1" ]
    end
    Tempfile.create([ "history", ".csv" ]) do |tempfile|
      tempfile.write(csv)
      tempfile.rewind
      upload = Rack::Test::UploadedFile.new(tempfile.path, "text/csv", original_filename: "history.csv")

      assert_no_difference -> { connection.snapshots.count } do
        post settings_csv_import_path, params: { connection_id: connection.id, file: upload }
      end
    end
    assert_redirected_to settings_data_path(anchor: "csv-import")
  end
end
