module Api
  module V1
    class GuestsController < BaseController
      # POST /api/v1/guests  { language_pair?, level? } → { token, user }
      def create
        pair = LanguagePair.active.find_by(code: params[:language_pair])
        level = Cefr::LEVELS.include?(params[:level]) ? params[:level] : nil
        user = User.create!(guest: true, language_pair: pair, self_level: level, onboarded_at: (Time.current if pair))
        render json: issue_token(user), status: :created
      end
    end
  end
end
