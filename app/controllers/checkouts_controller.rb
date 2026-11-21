# "Оплатить" on the paywall. In fake_door mode (default) we only measure intent: log
# checkout_clicked and ask for an email; PAYMENTS_MODE=stripe arrives in wave 7.
class CheckoutsController < ApplicationController
  include ReaderIdentity

  allow_unauthenticated_access

  def create
    plan = Pricing::PLANS.include?(params[:plan]) ? params[:plan] : "yearly"
    episode = Episode.find_by(id: params[:episode_id])
    track("checkout_clicked", user: current_reader, episode: episode, plan: plan, payments_mode: Pricing.mode)

    redirect_to new_waitlist_entry_path(plan: plan, episode_id: episode&.id)
  end
end
