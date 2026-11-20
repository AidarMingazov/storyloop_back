# Readers start without signing up: the first visit to a reader page creates a guest user
# with a normal session. Sign-up later fills in email and password on the same record (wave 4).
module ReaderIdentity
  extend ActiveSupport::Concern

  private
    def current_reader
      resume_session&.user || start_guest_session
    end

    def start_guest_session
      start_new_session_for(User.create!(guest: true)).user
    end
end
