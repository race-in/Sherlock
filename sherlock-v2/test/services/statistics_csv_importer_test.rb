require "csv"
require "test_helper"

class StatisticsCsvImporterTest < ActiveSupport::TestCase
  test "imports the existing history CSV format with immutable provenance" do
    connection = connections(:alice_redacted)
    user = users(:alice)
    observed_at = 4.days.ago.change(usec: 0)
    headers = [ "time", *History::STATS, *History::STATS.first(3).map { "#{_1}_change" }, "interval_ratio", "note" ]
    values = headers.index_with { nil }.merge(
      "time" => observed_at.iso8601, "uploaded" => "0", "downloaded" => "0",
      "ratio" => "1.2500", "seeding" => "12", "note" => "Imported from spreadsheet"
    )
    csv = CSV.generate do |writer|
      writer << headers
      writer << headers.map { values[_1] }
      writer << headers.map { values[_1] } # Duplicate inside the same file is ignored.
    end

    assert_equal 1, StatisticsCsvImporter.import!(connection:, user:, csv_text: csv)
    snapshot = connection.snapshots.find_by!(created_at: observed_at)
    assert_equal "csv_import", snapshot.source
    assert_equal user, snapshot.created_by_user
    assert_equal 0, snapshot.uploaded
    assert_equal 0, snapshot.downloaded
    assert_equal BigDecimal("1.25"), snapshot.ratio
    assert_equal "Imported from spreadsheet", snapshot.note
    assert_match(/\A[0-9a-f-]{36}\z/, snapshot.import_batch_id)
    assert_equal 0, StatisticsCsvImporter.import!(connection:, user:, csv_text: csv)
  end

  test "invalid later rows roll back the whole file before inserting anything" do
    connection = connections(:alice_redacted)
    user = users(:alice)
    csv = CSV.generate do |writer|
      writer << %w[time uploaded downloaded seeding]
      writer << [ 2.days.ago.iso8601, "10", "5", "2" ]
      writer << [ 1.day.ago.iso8601, "-1", "5", "2" ]
    end

    assert_no_difference -> { connection.snapshots.count } do
      error = assert_raises(ArgumentError) { StatisticsCsvImporter.import!(connection:, user:, csv_text: csv) }
      assert_match "CSV row 3", error.message
    end
  end

  test "requires core columns and rejects unknown columns and future observations" do
    connection = connections(:alice_redacted)
    user = users(:alice)
    missing = CSV.generate { |writer| writer << %w[time uploaded]; writer << [ 1.day.ago.iso8601, "1" ] }
    unknown = CSV.generate do |writer|
      writer << %w[time uploaded downloaded shell]
      writer << [ 1.day.ago.iso8601, "1", "1", "x" ]
    end
    future = CSV.generate do |writer|
      writer << %w[time uploaded downloaded]
      writer << [ 1.day.from_now.iso8601, "1", "1" ]
    end
    no_offset = CSV.generate do |writer|
      writer << %w[time uploaded downloaded]
      writer << [ Time.current.strftime("%Y-%m-%dT%H:%M:%S"), "1", "1" ]
    end

    [ missing, unknown, future, no_offset ].each do |csv|
      assert_no_difference -> { connection.snapshots.count } do
        assert_raises(ArgumentError) { StatisticsCsvImporter.import!(connection:, user:, csv_text: csv) }
      end
    end
  end

  test "rejects missing timestamps, malformed row widths, oversized content and cross-account calls" do
    connection = connections(:alice_redacted)
    user = users(:alice)
    missing_time = CSV.generate { |writer| writer << %w[time uploaded downloaded]; writer << [ nil, "1", "1" ] }
    malformed_width = "time,uploaded,downloaded,note\n#{2.days.ago.iso8601},1,1\n"

    [ missing_time, malformed_width ].each do |csv|
      assert_no_difference -> { connection.snapshots.count } do
        assert_raises(ArgumentError) { StatisticsCsvImporter.import!(connection:, user:, csv_text: csv) }
      end
    end

    assert_raises(ArgumentError) do
      StatisticsCsvImporter.import!(connection:, user:, csv_text: "x" * (StatisticsCsvImporter::MAX_BYTES + 1))
    end

    assert_raises(ArgumentError) do
      StatisticsCsvImporter.import!(connection:, user: users(:bob), csv_text: "time,uploaded,downloaded\n")
    end
  end

  test "does not accept malformed UTF-8 or out-of-range decimal values" do
    connection = connections(:alice_redacted)
    user = users(:alice)
    bad_decimal = CSV.generate do |writer|
      writer << %w[time uploaded downloaded ratio]
      writer << [ 1.day.ago.iso8601, "1", "1", "1.12345" ]
    end

    assert_raises(ArgumentError) do
      StatisticsCsvImporter.import!(connection:, user:, csv_text: bad_decimal)
    end
    assert_raises(ArgumentError) do
      StatisticsCsvImporter.import!(connection:, user:, csv_text: "\xFF".b)
    end
  end
end
