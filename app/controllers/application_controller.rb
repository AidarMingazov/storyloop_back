class ApplicationController < ActionController::Base
  include Authentication
  include Tracking

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  around_action :switch_locale

  private
    # Interface language = the learner's native language: their pair, else the browser's language.
    def switch_locale(&action)
      I18n.with_locale(request_locale, &action)
    end

    def request_locale
      resume_session&.user&.ui_locale || browser_locale || I18n.default_locale
    end

    def browser_locale
      request.headers["Accept-Language"].to_s.downcase.scan(/\b[a-z]{2}\b/)
             .map(&:to_sym).find { |locale| I18n.available_locales.include?(locale) }
    end
end
