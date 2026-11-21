# Readers start without signing up: the first reader action creates a guest user with a normal
# session. Sign-up later fills in email and password on the same record, so progress, words and
# the analytics id carry over untouched.
module ReaderIdentity
  extend ActiveSupport::Concern

  private
    def current_reader
      resume_session&.user || start_guest_session
    end

    def start_guest_session(**attrs)
      id = visitor_id.presence
      id = SecureRandom.uuid if id.nil? || User.exists?(analytics_id: id)
      user = User.create!(guest: true, analytics_id: id, utm: stored_utm, referrer: stored_referrer, **attrs)
      adopt_visitor_id(user)
      start_new_session_for(user).user
    end

    # Signing in on a device where someone read as a guest keeps what they did.
    def sign_in_keeping_guest_progress(user)
      guest = resume_session&.user
      user.absorb_guest!(guest) if guest&.guest? && guest != user
      start_new_session_for(user)
      adopt_visitor_id(user)
    end
end
