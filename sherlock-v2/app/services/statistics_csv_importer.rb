require "csv"

class StatisticsCsvImporter
  MAX_BYTES = 50.megabytes
  MAX_ROWS = 100_000
  ALLOWED_HEADERS = %w[
    time uploaded downloaded buffer ratio required_ratio bonus_points seeding leeching snatched hit_and_runs
    uploads forum_posts torrent_comments uploaded_change downloaded_change buffer_change interval_ratio note
  ].freeze
  REQUIRED_HEADERS = %w[time uploaded downloaded].freeze
  INTEGER_FIELDS = %w[uploaded downloaded seeding leeching snatched hit_and_runs uploads forum_posts torrent_comments].freeze
  DECIMAL_FIELDS = %w[ratio required_ratio bonus_points].freeze
  BIGINT_FIELDS = %w[uploaded downloaded].freeze
  MAX_BIGINT = 9_223_372_036_854_775_807
  MAX_INTEGER = 2_147_483_647

  def self.import!(connection:, user:, csv_text:)
    raise ArgumentError, "Choose one of your own trackers." unless connection.user_id == user.id

    csv_text = csv_text.to_s
    raise ArgumentError, "CSV is larger than 50 MB." if csv_text.bytesize > MAX_BYTES

    csv_text = csv_text.dup.force_encoding(Encoding::UTF_8)
    raise ArgumentError, "CSV isn't valid UTF-8." unless csv_text.valid_encoding?

    table = CSV.parse(csv_text, headers: true, encoding: "bom|utf-8")
    headers = table.headers&.map(&:to_s)
    raise ArgumentError, "CSV needs a header row." if headers.blank?
    raise ArgumentError, "CSV contains blank column names." if headers.any?(&:blank?)
    raise ArgumentError, "CSV contains duplicate column names." unless headers.uniq == headers

    missing = REQUIRED_HEADERS - headers
    raise ArgumentError, "CSV is missing required columns: #{missing.to_sentence}." if missing.any?
    unknown = headers - ALLOWED_HEADERS
    raise ArgumentError, "CSV has unsupported columns: #{unknown.to_sentence}." if unknown.any?
    raise ArgumentError, "CSV has more than #{MAX_ROWS} rows." if table.size > MAX_ROWS

    # Serialize imports for this connection. Two simultaneous uploads cannot both pass the
    # duplicate check and insert the same observation timestamp.
    connection.with_lock do
      known = connection.snapshots.pluck(:created_at).to_set(&:to_i)
      batch_id = SecureRandom.uuid
      rows = table.each_with_index.filter_map do |record, index|
        row_number = index + 2
        raise ArgumentError, "CSV row #{row_number}: the number of values does not match the header." unless record.fields.length == headers.length
        values = record.to_h
        next if values.values.all?(&:blank?)

        begin
          timestamp = values["time"].to_s
          raise ArgumentError, "time is required" if timestamp.blank?
          raise ArgumentError, "time must include an explicit UTC offset" unless timestamp.match?(/(?:Z|[+-]\d{2}:\d{2})\z/i)

          created_at = Time.iso8601(timestamp).change(usec: 0)
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
    end
  rescue CSV::MalformedCSVError, EncodingError
    raise ArgumentError, "CSV is malformed or isn't valid UTF-8."
  end

  def self.parse_integer(value, field:, required:)
    return nil if value.blank? && !required
    raise ArgumentError, "#{field} must be a whole number." if value.blank?

    raw = value.to_s
    raise ArgumentError, "#{field} must be a non-negative whole number." unless raw.match?(/\A\d+\z/)

    limit = BIGINT_FIELDS.include?(field) ? MAX_BIGINT : MAX_INTEGER
    raise ArgumentError, "#{field} is too large." if raw.length > limit.to_s.length
    number = Integer(raw, 10)
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
