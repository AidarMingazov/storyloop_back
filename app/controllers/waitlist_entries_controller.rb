class WaitlistEntriesController < ApplicationController
  include ReaderIdentity

  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to root_path, alert: t("auth.rate_limited") }

  def new
    @reader = resume_session&.user
    @entry = WaitlistEntry.new(email: @reader&.email_address, plan: params[:plan])
  end

  def create
    reader = current_reader
    @entry = WaitlistEntry.find_or_initialize_by(email: params.dig(:waitlist_entry, :email).to_s.strip.downcase)
    @entry.assign_attributes(plan: params.dig(:waitlist_entry, :plan), user: reader,
                             language_pair: reader.language_pair, source: "paywall",
                             utm: reader.utm.presence || stored_utm)
    if @entry.save
      track("waitlist_email_submitted", user: reader, plan: @entry.plan)
      redirect_to waitlist_entry_path(@entry)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
  end
end
