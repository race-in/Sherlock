module PreferenceParams
  private
    def preference_params
      params.expect(user: %i[time_zone byte_unit default_range theme is_chart_filled is_chart_points_shown is_tracker_name_short buffer_basis])
    end
end
