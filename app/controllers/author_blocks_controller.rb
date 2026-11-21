# "Hide author" (7.6): POST hides the author's stories from the feed and author pages for this reader,
# DELETE brings them back.
class AuthorBlocksController < ApplicationController
  include ReaderIdentity

  allow_unauthenticated_access

  def create
    author = User.find_by!(public_id: params[:author_public_id])
    block = current_reader.author_blocks.find_or_create_by(author: author)
    track("author_hidden", user: current_reader, author: author.public_id) if block.previously_new_record?
    redirect_to community_path, notice: t("stories.hide_author.done", name: author.author_name)
  rescue ActiveRecord::RecordNotUnique
    redirect_to community_path
  end

  def destroy
    author = User.find_by!(public_id: params[:author_public_id])
    current_reader.author_blocks.where(author: author).destroy_all
    redirect_to author_path(author.public_id), notice: t("stories.hide_author.undone")
  end
end
