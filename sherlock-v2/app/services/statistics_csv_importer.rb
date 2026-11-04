require "csv"

class StatisticsCsvImporter
  MAX_ROWS = 100_000
  ALLOWED_HEADERS = %w[
    time uploaded downloaded buffer ratio bonus_points seeding leeching snatched hit_and_runs
    uploads forum_posts torrent_comments uploaded_change downloaded_change buffer_change interval_ratio note
  ].freeze
  REQUIRED_HEADERS = %w[time uploaded downloaded].freeze
  INTEGER_FIELDS = %w[uploaded downloaded seeding leeching snatched hit_and_runs uploads forum_posts torrent_comments].freeze
  DECIMAL_FIELDS = %w[ratio required_ratio bonus_points].freeze
  BIGINT_FIELDS = %w[uploaded downloaded].freeze
  MAX_BIGINT = 9_223_372_036_854_775_807
  MAX_INTEGER = 2_147_483_647

  def self.import!(connection:, user:, csv_text:)
    table = CSV.parse(csv_text, headers: true, encoding: "bom|utf-8")
    headers = table.headers&.map(&:to_s)
    raise ArgumentError, "CSV needs a header row." if headers.blank?
    raise ArgumentError, "CSV contains duplicate column names." unless headers.uniq == headers
    missing = REQUIRED_HEADERS - headers
    raise ArgumentError, "CSV is missing required columns: #{missing.to_sentence}." if missing.any?
    unknown = headers - ALLOWED_HEADERS
    raise ArgumentError, "CSV has unsupported columns: #{unknown.to_sentence}." if unknown.any?
    raise ArgumentError, "CSV has more than #{MAX_ROWS} rows." if table.size > MAX_ROWS

    known = connection.snapshots.pluck(:created_at).to_set(&:to_i)
    batch_id = SecureRandom.uuid
    rows = table.each_with_index.filter_map do |record, index|
      values = record.to_h
      next if values.values.all?(&:blank?)

      row_number = index + 2
      begin
        created_at = Time.iso8601(values.fetch("time")).change(usec: 0)
        raise ArgumentError, "observation time is in the future" if created_at.future?

        attributes = INTEGER_FIELDS.index_with do |field|
          parse_integer(values[field], field:, required: BIGINT_FIELDS.include?(field))
        end.merge(DECIMAL_FIELDS.index_with { |field| parse_decimal(values[field], field:) })

        note = values["note"].presence
        raise ArgumentError, "note is longer than 500 characters" if note && note.length > 500

        next unless known.add?(created_at.to_i)

        attributes.merge(
          connection_id: connection.id, created_by_user_id: user.id, source: "csv_import",
          import_batch_id: batch_id, note:, created_at:, updated_at: created_at
        )
      rescue ArgumentError, TypeError, KeyError => error
        raise ArgumentError, "CSV row #{row_number}: #{error.message}."
      end
    end

    connection.snapshots.insert_all!(rows) if rows.any?
    rows.size
  rescue CSV::MalformedCSVError, EncodingError
    raise ArgumentError, "CSV is malformed or isn't valid UTF-8."
  end

  def self.parse_integer(value, field:, required:)
    return nil if value.blank? && !required
    raise ArgumentError, "#{field} must be a whole number." if value.blank?

    raw = value.to_s
    raise ArgumentError, "#{field} must be a non-negative whole number." unless raw.match?(/\A\d+\z/)

    number = Integer(raw, 10)
    limit = BIGINT_FIELDS.include?(field) ? MAX_BIGINT : MAX_INTEGER
    raise ArgumentError, "#{field} is too large." if number > limit
    number
  end
  private_class_method :parse_integer

  def self.parse_decimal(value, field:)
    return nil if value.blank?

    raw = value.to_s
    whole, fractional, extra = raw.split(".", 3)
    max_whole = field == "bonus_points" ? 14 : 8
    max_fraction = field == "bonus_points" ? 2 : 4
    valid = extra.nil? && whole.match?(/\A\d+\z/) && whole.length <= max_whole &&
      (fractional.nil? || (fractional.match?(/\A\d+\z/) && fractional.length <= max_fraction))
    raise ArgumentError, "#{field} exceeds the supported precision." unless valid

    BigDecimal(raw)
  end
  private_class_method :parse_decimal
end
