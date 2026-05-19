require 'rails_helper'

RSpec.describe Games::Bot do
  def make_seat(hole_cards:, stack: 1000, bet: 0, position: 0)
    { 'position' => position, 'name' => 'Bot 1', 'stack' => stack,
      'bet' => bet, 'hole_cards' => hole_cards, 'status' => 'active',
      'is_bot' => true, 'session_id' => 'bot_1' }
  end

  def make_state(seat, street: 'pre_flop', current_bet: 20, community_cards: [])
    { 'street' => street, 'current_bet' => current_bet,
      'min_raise' => 20, 'pot' => 40, 'community_cards' => community_cards,
      'seats' => [seat] }
  end

  describe '.decide' do
    it 'returns a hash with an action key' do
      seat = make_seat(hole_cards: %w[Ah Ks])
      state = make_state(seat)
      result = described_class.decide(state, 0)
      expect(result).to have_key('action')
      expect(%w[fold call raise check]).to include(result['action'])
    end

    it 'raises with premium pre-flop hands (pocket aces)' do
      seat = make_seat(hole_cards: %w[Ah As])
      state = make_state(seat)
      result = described_class.decide(state, 0)
      expect(result['action']).to eq 'raise'
    end

    it 'raises with a made flush on the flop' do
      seat = make_seat(hole_cards: %w[Ah Kh])
      state = make_state(seat, street: 'flop', community_cards: %w[2h 5h 7h])
      result = described_class.decide(state, 0)
      expect(result['action']).to eq 'raise'
    end

    it 'includes amount when raising' do
      seat = make_seat(hole_cards: %w[Ah As])
      state = make_state(seat)
      result = described_class.decide(state, 0)
      if result['action'] == 'raise'
        expect(result['amount']).to be_a(Integer)
        expect(result['amount']).to be >= 40
      end
    end

    it 'checks instead of calling when current_bet is 0' do
      seat = make_seat(hole_cards: %w[2d 7s], bet: 0)
      srand(0)
      state = make_state(seat, current_bet: 0)
      # weak hand + no bet = check (or bluff raise, but srand(0) gives fold → check)
      result = described_class.decide(state, 0)
      expect(result['action']).not_to eq 'call'
    end
  end
end
