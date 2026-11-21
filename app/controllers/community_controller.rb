# GET /community — "Community stories" (7.7).
class CommunityController < ApplicationController
  allow_unauthenticated_access

  def index
    @reader = resume_session&.user
    @pairs = LanguagePair.active.order(:code)
    @pair = params.key?(:pair) ? @pairs.find_by(code: params[:pair]) : @reader&.language_pair
    @feed = CommunityFeed.new(reader: @reader, pair: @pair, level: params[:level], sort: params[:sort], page: params[:page])
  end
end
