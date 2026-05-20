require 'rails_helper'

RSpec.describe BotActionJob, type: :job do
  # Two-player state with a bot at `position` acting first
  def bot_turn_state(bot_position:)
    human_position = (bot_position + 1) % 6
    deck = Games::Deck.new
    seats = Array.new(6) do |i|
      if i == bot_position
        { 'position' => i, 'name' => 'Bot 1', 'stack' => 990, 'bet' => 10,
          'hole_cards' => deck.deal(2), 'status' => 'active',
          'is_bot' => true, 'session_id' => "bot_#{i}" }
      elsif i == human_position
        { 'position' => i, 'name' => 'Human', 'stack' => 980, 'bet' => 20,
          'hole_cards' => deck.deal(2), 'status' => 'active',
          'is_bot' => false, 'session_id' => "human_#{i}" }
      else
        { 'position' => i, 'name' => nil, 'stack' => 0, 'bet' => 0,
          'hole_cards' => [], 'status' => 'empty', 'is_bot' => false, 'session_id' => nil }
      end
    end
    {
      'status' => 'playing', 'street' => 'pre_flop', 'hand_number' => 1,
      'dealer_position' => bot_position, 'current_position' => bot_position,
      'current_bet' => 20, 'min_raise' => 20, 'pot' => 30,
      'players_to_act' => 1, 'community_cards' => [], 'last_action' => nil,
      'deck' => deck.to_a,
      'seats' => seats
    }
  end

  describe '#perform' do
    it 'acts when the bot is at current_position' do
      table = create(:table, state: bot_turn_state(bot_position: 0))
      described_class.perform_now(table.slug, 0)
      table.reload
      expect(table.state['last_action']).to be_present
    end

    it 'skips without error when position is no longer current' do
      table = create(:table, state: bot_turn_state(bot_position: 0))
      expect { described_class.perform_now(table.slug, 5) }.not_to raise_error
      table.reload
      expect(table.state['current_position']).to eq 0
    end

    it 'does not double-act when called again with an already-acted position' do
      table = create(:table, state: bot_turn_state(bot_position: 0))
      described_class.perform_now(table.slug, 0)
      state_after_first = table.reload.state

      described_class.perform_now(table.slug, 0)
      expect(table.reload.state['current_position']).to eq state_after_first['current_position']
    end

    it 'does not raise when an InvalidActionError occurs mid-race' do
      table = create(:table, state: bot_turn_state(bot_position: 0))
      allow_any_instance_of(Table).to receive(:apply_action)
        .and_raise(Games::NlHoldem::InvalidActionError, 'Not this player\'s turn')
      expect { described_class.perform_now(table.slug, 0) }.not_to raise_error
    end

    it 'enqueues NextHandJob when the action ends the hand' do
      table = create(:table, state: bot_turn_state(bot_position: 0))
      allow(Games::Bot).to receive(:decide).and_return({ 'action' => 'fold' })
      expect { described_class.perform_now(table.slug, 0) }
        .to have_enqueued_job(NextHandJob)
    end
  end
end
