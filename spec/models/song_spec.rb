require 'rails_helper'

RSpec.describe Song, type: :model do
  describe '#apply_diff' do
    subject(:song) { create(:song) }

    it 'toggles a melody cell on' do
      song.apply_diff('type' => 'toggle', 'row' => 0, 'step' => 3, 'value' => true)
      expect(song.reload.state['grid'][0][3]).to be true
    end

    it 'toggles a melody cell off' do
      song.state['grid'][1][5] = true
      song.save!
      song.apply_diff('type' => 'toggle', 'row' => 1, 'step' => 5, 'value' => false)
      expect(song.reload.state['grid'][1][5]).to be false
    end

    it 'toggles a kick step' do
      song.apply_diff('type' => 'kick_toggle', 'step' => 4, 'value' => true)
      expect(song.reload.state['kick'][4]).to be true
    end

    it 'sets kick_active' do
      song.apply_diff('type' => 'kick_active', 'value' => true)
      expect(song.reload.state['kick_active']).to be true
    end

    it 'updates bpm' do
      song.apply_diff('type' => 'bpm', 'value' => 140)
      expect(song.reload.state['bpm']).to eq 140
    end

    it 'updates waveform' do
      song.apply_diff('type' => 'waveform', 'value' => 'square')
      expect(song.reload.state['waveform']).to eq 'square'
    end

    it 'updates decay' do
      song.apply_diff('type' => 'decay', 'value' => 0.8)
      expect(song.reload.state['decay']).to eq 0.8
    end

    it 'updates reverb' do
      song.apply_diff('type' => 'reverb', 'value' => 50)
      expect(song.reload.state['reverb']).to eq 50
    end

    it 'updates volume' do
      song.apply_diff('type' => 'volume', 'value' => -12)
      expect(song.reload.state['volume']).to eq(-12)
    end

    it 'clears the grid and kick' do
      song.update!(state: song.state.merge('grid' => Array.new(12) { Array.new(16, true) },
                                           'kick' => Array.new(16, true)))
      song.apply_diff('type' => 'clear')
      reloaded = song.reload
      expect(reloaded.state['grid'].flatten).to all(be false)
      expect(reloaded.state['kick']).to all(be false)
    end

    it 'applies a full_sync' do
      new_grid = Array.new(12) { Array.new(16, false) }
      new_grid[0][0] = true
      song.apply_diff('type' => 'full_sync', 'grid' => new_grid, 'kick' => Array.new(16, false), 'kick_active' => true)
      reloaded = song.reload
      expect(reloaded.state['grid'][0][0]).to be true
      expect(reloaded.state['kick_active']).to be true
    end
  end

  describe 'slug generation' do
    it 'generates a slug on create' do
      song = Song.create!
      expect(song.slug).to match(/\A[a-z0-9]{8}\z/)
    end

    it 'generates unique slugs' do
      slugs = Array.new(5) { Song.create!.slug }
      expect(slugs.uniq.length).to eq 5
    end
  end
end