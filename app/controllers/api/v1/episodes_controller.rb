module Api
  module V1
    class EpisodesController < BaseController
      # GET /api/v1/episodes/:id → episode JSON (absolute media URLs); 402 for paid episodes without access
      def show
        episode = Episode.published.includes(series: [ :language_pair, :characters ]).find(params[:id])
        unless current_user&.can_read?(episode) || episode.free?
          return render json: { error: "subscription_required", paywall: { plans: Pricing.for(episode.series.language_pair) } },
                        status: :payment_required
        end

        if current_user
          progress = current_user.reading_progresses.find_or_create_by!(episode: episode)
          track("episode_started", episode: episode) if progress.previously_new_record?
        end
        render json: EpisodePayload.new(episode, user: current_user, media_host: { host: request.host_with_port, protocol: request.protocol })
      end
    end
  end
end
