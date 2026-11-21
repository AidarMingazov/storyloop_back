# GET /u/:public_id — an author's public stories (7.7).
class AuthorsController < ApplicationController
  allow_unauthenticated_access

  def show
    @author = User.not_banned.find_by!(public_id: params[:public_id])
    @reader = resume_session&.user
    @hidden = @reader&.hides_author?(@author)
    @feed = CommunityFeed.new(author: @author, reader: @hidden ? nil : @reader, page: params[:page])
  end
end
