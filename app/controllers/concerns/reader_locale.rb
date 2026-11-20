# Reader-facing pages speak the learner's native language (en-ru → ru, ko-en → en).
module ReaderLocale
  extend ActiveSupport::Concern

  included do
    around_action :switch_to_reader_locale
  end

  private
    def switch_to_reader_locale(&action)
      locale = resume_session&.user&.ui_locale || I18n.default_locale
      I18n.with_locale(locale, &action)
    end
end
