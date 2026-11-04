class Connections::ManualSnapshotsController < ApplicationController
  INTEGER_FIELDS = %i[uploaded downloaded seeding leeching snatched hit_and_runs uploads forum_posts torrent_comments].freeze
  DECIMAL_FIELDS = %i[ratio required_ratio bonus_points].freeze
  MAX_BIGINT = 9_223_372_036_854_775_807
  MAX_INTEGER = 2_147_483_647

  def create
    @connection = Current.user.connections.find(params[:connection_id])
    input = params.expect(snapshot: %i[
      uploaded downloaded ratio required_ratio bonus_points seeding leeching snatched hit_and_runs
      uploads forum_posts torrent_comments created_at note
    ])

    attributes = INTEGER_FIELDS.index_with { |field| parse_integer(input[field], field:, required: %i[uploaded downloaded].include?(field)) }
      .merge(DECIMAL_FIELDS.index_with { |field| parse_decimal(input[field], field:) })
    observed_at = input[:created_at].present? ? Time.zone.parse(input[:created_at]) : Time.current
    raise ArgumentError, "Observation time is invalid." unless observed_at
    raise ArgumentError, "Observation time can't be in the future." if observed_at > Time.current
    note = input[:note].presence
    raise ArgumentError, "Note must be 500 characters or fewer." if note && note.length > 500

    @connection.snapshots.create!(attributes.merge(
      created_at: observed_at, source: :manual, note:, created_by_user: Current.user
    ))
    redirect_to connection_path(@connection), notice: "Manual statistics saved. A new history point was added."
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to connection_path(@connection || Current.user.connections.find(params[:connection_id])),
      alert: error.message
  end

  private
    def parse_integer(value, field:, required:)
      return nil if value.blank? && !required
      raise ArgumentError, "Uploaded and downloaded must be whole numbers of bytes." if value.blank?

      raw = value.to_s
      raise ArgumentError, "Counts and byte values must be non-negative whole numbers." unless raw.match?(/\A\d+\z/)

      number = Integer(raw, 10)
      limit = %i[uploaded downloaded].include?(field) ? MAX_BIGINT : MAX_INTEGER
      raise ArgumentError, "A number is too large." if number > limit
      number
    end

    def parse_decimal(value, field:)
      return nil if value.blank?

      raw = value.to_s
      whole, fractional, extra = raw.split(".", 3)
      max_whole = field == :bonus_points ? 14 : 8
      max_fraction = field == :bonus_points ? 2 : 4
      valid = extra.nil? && whole.match?(/\A\d+\z/) && whole.length <= max_whole &&
        (fractional.nil? || (fractional.match?(/\A\d+\z/) && fractional.length <= max_fraction))
      raise ArgumentError, "Ratios and bonus points exceed the supported precision." unless valid

      BigDecimal(raw)
    end
end
