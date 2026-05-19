class Audio::SongsController < ApplicationController
  layout 'audio'

  def create
    song = Song.create!
    render json: { slug: song.slug, state: song.state }
  end

  def show
    @song = Song.find_by!(slug: params[:slug])
    render 'audio/sequencer'
  end
end
