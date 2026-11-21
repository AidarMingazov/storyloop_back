# "Оплатить" on the paywall. In fake_door mode (default) we only measure intent: log
# checkout_clicked and ask for an email; PAYMENTS_MODE=stripe arrives in wave 7.
# reason: episode (paid episode) | generation (free story generations used up, 7.5).
class CheckoutsController < ApplicationController
  include ReaderIdentity

  allow_unauthenticated_access

  REASONS = %w[episode generation].freeze

  def create
    plan = Pricing::PLANS.include?(params[:plan]) ? params[:plan] : "yearly"
    episode = Episode.find_by(id: params[:episode_id])
    reason = REASONS.include?(params[:reason]) ? params[:reason] : "episode"
    track("checkout_clicked", user: current_reader, episode: episode, plan: plan, payments_mode: Pricing.mode, reason: reason)

    redirect_to new_waitlist_entry_path(plan: plan, episode_id: episode&.id)
  end
end
