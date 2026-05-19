class AudioController < ApplicationController
  layout 'audio'

  def index
    @recent_songs = Song.order(created_at: :desc).limit(20)
  end

  def new_song
    @song = nil
    render 'audio/sequencer'
  end
end
