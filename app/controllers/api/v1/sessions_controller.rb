module Api
  module V1
    class SessionsController < BaseController
      rate_limit to: 10, within: 3.minutes, only: :create, with: -> { render_error :too_many_requests, "rate_limited" }

      # POST /api/v1/sessions  { email_address, password } → { token, user }
      def create
        user = User.authenticate_by(email_address: params.expect(:email_address), password: params.expect(:password))
        return render_error(:unauthorized, "invalid_credentials") unless user

        user.absorb_guest!(current_user) if current_user&.guest?
        render json: issue_token(user), status: :created
      end

      # DELETE /api/v1/session
      def destroy
        current_session&.destroy
        head :no_content
      end
    end
  end
end
