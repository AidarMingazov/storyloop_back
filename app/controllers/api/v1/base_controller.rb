module Api
  module V1
    # JSON API for native clients. Auth: `Authorization: Bearer <token>` from POST /api/v1/guests
    # or POST /api/v1/sessions. Same episode JSON as the web reader (EpisodePayload).
    class BaseController < ActionController::API
      include ActionController::HttpAuthentication::Token::ControllerMethods

      rescue_from ActiveRecord::RecordNotFound, with: -> { render_error :not_found, "not_found" }
      rescue_from ActionController::ParameterMissing, with: ->(e) { render_error :unprocessable_entity, "parameter_missing", e.message }

      private
        def current_session
          return @current_session if defined?(@current_session)
          @current_session = authenticate_with_http_token { |token, _| Session.find_by(token: token) }
        end

        def current_user = current_session&.user

        def require_user!
          render_error(:unauthorized, "unauthorized", "Send Authorization: Bearer <token>") unless current_user
        end

        def render_error(status, code, message = nil)
          render json: { error: code, message: message }.compact, status: status
        end

        def track(event, episode: nil, **properties)
          Analytics.track(event, distinct_id: current_user&.analytics_id,
                                 properties: Analytics.context(user: current_user, episode: episode).merge(client: "api", **properties))
        end

        def issue_token(user)
          session = user.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip)
          { token: session.token, user: { id: user.id, guest: user.guest?, language_pair: user.language_pair&.code } }
        end
    end
  end
end
