# Visitor id cookie (= PostHog distinct id), first-touch UTM, and a `track` helper for controllers.
module Tracking
  extend ActiveSupport::Concern

  included do
    before_action :ensure_visitor_id, :remember_utm, :remember_ref
    helper_method :visitor_id, :analytics_context
  end

  private
    def visitor_id
      cookies[:visitor_id]
    end

    def ensure_visitor_id
      return if cookies[:visitor_id].present?
      cookies.permanent[:visitor_id] = { value: SecureRandom.uuid, same_site: :lax }
    end

    # After sign-in the device continues as the account's id, so browser and server events match.
    def adopt_visitor_id(user)
      cookies.permanent[:visitor_id] = { value: user.analytics_id, same_site: :lax }
    end

    def forget_visitor_id
      cookies.delete(:visitor_id)
    end

    def remember_utm
      return if cookies[:utm].present?
      utm = request.query_parameters.slice(*Analytics::UTM_KEYS).compact_blank
      cookies.permanent[:utm] = { value: utm.to_json, same_site: :lax } if utm.any?
    end

    # Share links carry ?ref=<sharer's public id>; first touch wins, like UTM.
    def remember_ref
      ref = params[:ref].to_s
      return if cookies[:ref].present? || !ref.match?(/\A[1-9A-HJ-NP-Za-km-z]{10}\z/)
      cookies.permanent[:ref] = { value: ref, same_site: :lax }
    end

    def stored_referrer
      User.find_by(public_id: cookies[:ref]) if cookies[:ref].present?
    end

    def stored_utm
      JSON.parse(cookies[:utm].to_s).slice(*Analytics::UTM_KEYS)
    rescue JSON::ParserError
      {}
    end

    def track(event, user: Current.user, episode: nil, **properties)
      Analytics.track(event, distinct_id: user&.analytics_id || visitor_id,
                             properties: analytics_context(user: user, episode: episode).merge(properties))
    end

    def analytics_context(user: Current.user, episode: nil)
      Analytics.context(user: user, episode: episode, utm: stored_utm)
    end
end
