class SequencerChannel < ApplicationCable::Channel
  def subscribed
    song = Song.find_by(slug: params[:slug])
    return reject unless song

    stream_from "sequencer_#{params[:slug]}"
  end

  def receive(data)
    song = Song.find_by!(slug: params[:slug])
    song.apply_diff(data)
    ActionCable.server.broadcast("sequencer_#{params[:slug]}", data)
  end
end
