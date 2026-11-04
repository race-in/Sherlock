# The profile a member is proving theirs (ProfileClaim), kept in the session between pasting the link,
# checking it and saving it. One at a time: starting another replaces it.
module ProfileClaims
  extend ActiveSupport::Concern

  included do
    helper_method :profile_claim
  end

  private
    def profile_claim
      @profile_claim ||= ProfileClaim.from_session(session[:profile_claim])
    end

    def save_profile_claim(claim)
      @profile_claim = claim
      session[:profile_claim] = claim.to_session
    end

    def forget_profile_claim
      @profile_claim = nil
      session.delete(:profile_claim)
    end

    # Reads the profile once, keeps what Check found, and renders the error when it didn't.
    def check_profile_claim(claim)
      claim.check!
      yield
    rescue Engines::Error => error
      @check_error = error
      render_profile_step
    ensure
      save_profile_claim(claim)
    end
end
