require 'rails_helper'

RSpec.describe SequencerChannel, type: :channel do
  let(:song) { create(:song) }

  describe '#subscribed' do
    it 'streams from the song slug when song exists' do
      subscribe slug: song.slug
      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from("sequencer_#{song.slug}")
    end

    it 'rejects subscription when slug does not exist' do
      subscribe slug: 'nosuchsong'
      expect(subscription).to be_rejected
    end
  end

  describe '#receive' do
    before { subscribe slug: song.slug }

    it 'broadcasts the received data back to the stream' do
      data = { 'type' => 'toggle', 'row' => 0, 'step' => 1, 'value' => true, 'client_id' => 'abc123' }
      expect {
        perform :receive, data
      }.to have_broadcasted_to("sequencer_#{song.slug}").with(including(data))
    end

    it 'persists a toggle diff to the song' do
      perform :receive, 'type' => 'toggle', 'row' => 2, 'step' => 7, 'value' => true, 'client_id' => 'abc'
      expect(song.reload.state['grid'][2][7]).to be true
    end

    it 'persists a bpm change to the song' do
      perform :receive, 'type' => 'bpm', 'value' => 160, 'client_id' => 'abc'
      expect(song.reload.state['bpm']).to eq 160
    end

    it 'raises an error for an unknown slug' do
      # Simulate slug disappearing after subscribe (edge case)
      song.destroy
      expect {
        perform :receive, 'type' => 'bpm', 'value' => 100, 'client_id' => 'abc'
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end