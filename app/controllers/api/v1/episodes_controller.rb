module Api
  module V1
    class EpisodesController < BaseController
      # GET /api/v1/episodes/:id and GET /api/v1/s/:share_token → episode JSON (absolute media URLs).
      # User stories follow StoryAccess, as in the web reader: a link story opens only by its share token,
      # a private one only for its author; anything not readable is 404. 402 for paid episodes without access.
      def show
        episode = find_episode
        access = StoryAccess.new(episode, current_user, via_link: params[:share_token].present?)
        return render_error(:not_found, "not_found") unless access.readable?

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

      private
        def find_episode
          scope = Episode.published.includes(series: [ :language_pair, :characters, :author ])
          params[:share_token] ? scope.find_by!(share_token: params[:share_token]) : scope.find(params[:id])
        end
    end
  end
end
