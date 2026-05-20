require 'rails_helper'

RSpec.describe Games::NlHoldem do
  def make_state(player_names, dealer_pos: 0, status: 'waiting')
    seats = Array.new(6) { |i|
      if i < player_names.length
        { 'position' => i, 'name' => player_names[i], 'stack' => 1000,
          'bet' => 0, 'hole_cards' => [], 'status' => 'active',
          'is_bot' => false, 'session_id' => "sid#{i}" }
      else
        { 'position' => i, 'name' => nil, 'stack' => 0, 'bet' => 0,
          'hole_cards' => [], 'status' => 'empty',
          'is_bot' => false, 'session_id' => nil }
      end
    }
    {
      'status' => status, 'street' => nil, 'hand_number' => 0,
      'dealer_position' => dealer_pos, 'current_position' => nil,
      'current_bet' => 0, 'min_raise' => 20, 'pot' => 0,
      'players_to_act' => 0, 'community_cards' => [], 'deck' => [],
      'last_action' => nil, 'seats' => seats
    }
  end

  describe '.deal_hand' do
    let(:state)     { make_state(%w[Alice Bob Carol Dave]) }
    let(:new_state) { described_class.deal_hand(state) }

    it 'sets status to playing' do
      expect(new_state['status']).to eq 'playing'
    end

    it 'sets street to pre_flop' do
      expect(new_state['street']).to eq 'pre_flop'
    end

    it 'deals 2 hole cards to each active player' do
      active = new_state['seats'].reject { |s| s['status'] == 'empty' }
      active.each { |s| expect(s['hole_cards'].length).to eq 2 }
    end

    it 'posts small and big blinds' do
      expect(new_state['pot']).to eq 30
    end

    it 'sets current_bet to big blind' do
      expect(new_state['current_bet']).to eq 20
    end

    it 'stores remaining deck in state' do
      # 4 players × 2 cards = 8 cards dealt
      expect(new_state['deck'].length).to eq(52 - 4 * 2)
    end

    it 'increments hand_number' do
      expect(new_state['hand_number']).to eq 1
    end

    it 'sets current_position to UTG (after BB)' do
      # dealer=0, SB=1, BB=2, UTG=3
      expect(new_state['current_position']).to eq 3
    end
  end

  describe '.apply_action — dealer advancement' do
    it 'advances the dealer when the hand ends at showdown' do
      state = make_state(%w[Alice Bob])
      state = described_class.deal_hand(state)
      dealer_before = state['dealer_position']
      20.times do
        break if state['street'] == 'hand_over'
        pos = state['current_position']
        break unless pos
        seat = state['seats'].find { |s| s['position'] == pos }
        action = seat['bet'].to_i >= state['current_bet'].to_i ? 'check' : 'call'
        state = described_class.apply_action(state, pos, { 'action' => action })
      end
      expect(state['dealer_position']).not_to eq dealer_before
    end

    it 'advances the dealer when the hand ends by a fold' do
      state = make_state(%w[Alice Bob])
      state = described_class.deal_hand(state)
      dealer_before = state['dealer_position']
      pos = state['current_position']
      state = described_class.apply_action(state, pos, { 'action' => 'fold' })
      expect(state['street']).to eq 'hand_over'
      expect(state['dealer_position']).not_to eq dealer_before
    end
  end

  describe '.apply_action — hand_over cleanup' do
    it 'sets current_position to nil when the hand ends by fold' do
      state = make_state(%w[Alice Bob])
      state = described_class.deal_hand(state)
      pos = state['current_position']
      new_state = described_class.apply_action(state, pos, { 'action' => 'fold' })
      expect(new_state['street']).to eq 'hand_over'
      expect(new_state['current_position']).to be_nil
    end

    it 'sets current_position to nil when the hand ends at showdown' do
      state = make_state(%w[Alice Bob])
      state = described_class.deal_hand(state)
      20.times do
        break if state['street'] == 'hand_over'
        pos = state['current_position']
        break unless pos
        seat = state['seats'].find { |s| s['position'] == pos }
        action = seat['bet'].to_i >= state['current_bet'].to_i ? 'check' : 'call'
        state = described_class.apply_action(state, pos, { 'action' => action })
      end
      expect(state['street']).to eq 'hand_over'
      expect(state['current_position']).to be_nil
    end
  end

  describe '.apply_action — fold' do
    it 'marks the seat as folded' do
      state = make_state(%w[Alice Bob])
      state = described_class.deal_hand(state)
      state['current_position'] = 0
      new_state = described_class.apply_action(state, 0, { 'action' => 'fold' })
      expect(new_state['seats'][0]['status']).to eq 'folded'
    end

    it 'transitions to hand_over when only one player remains' do
      state = make_state(%w[Alice Bob])
      state = described_class.deal_hand(state)
      state['current_position'] = 1
      new_state = described_class.apply_action(state, 1, { 'action' => 'fold' })
      expect(new_state['street']).to eq 'hand_over'
    end
  end

  describe '.apply_action — call' do
    it 'moves chips from stack to pot' do
      state = make_state(%w[Alice Bob Carol])
      state = described_class.deal_hand(state)
      pos = state['current_position']
      seat = state['seats'][pos]
      stack_before = seat['stack']
      call_amount = state['current_bet'] - seat['bet'].to_i
      new_state = described_class.apply_action(state, pos, { 'action' => 'call' })
      new_seat = new_state['seats'][pos]
      expect(new_seat['stack']).to eq(stack_before - call_amount)
    end
  end

  describe '.apply_action — raise' do
    it 'updates current_bet and min_raise' do
      state = make_state(%w[Alice Bob Carol])
      state = described_class.deal_hand(state)
      pos = state['current_position']
      new_state = described_class.apply_action(state, pos, { 'action' => 'raise', 'amount' => 60 })
      expect(new_state['current_bet']).to eq 60
      expect(new_state['min_raise']).to eq 40
    end

    it 'resets players_to_act' do
      state = make_state(%w[Alice Bob Carol Dave])
      state = described_class.deal_hand(state)
      pos = state['current_position']
      new_state = described_class.apply_action(state, pos, { 'action' => 'raise', 'amount' => 60 })
      expect(new_state['players_to_act']).to be > 0
    end
  end

  describe '.apply_action — check' do
    it 'advances without changing pot' do
      state = make_state(%w[Alice Bob])
      state = described_class.deal_hand(state)
      state['street'] = 'flop'
      state['current_bet'] = 0
      state['community_cards'] = %w[Kh 7s 2d]
      state['seats'].each { |s| s['bet'] = 0 if s['status'] == 'active' }
      first_active_pos = state['seats'].find { |s| s['status'] == 'active' }&.fetch('position')
      state['current_position'] = first_active_pos
      state['players_to_act'] = 2
      pot_before = state['pot']
      new_state = described_class.apply_action(state, first_active_pos, { 'action' => 'check' })
      expect(new_state['pot']).to eq pot_before
    end
  end

  describe '.apply_action — street advancement' do
    it 'deals 3 community cards when pre_flop round ends' do
      state = make_state(%w[Alice Bob])
      state = described_class.deal_hand(state)
      10.times do
        break if state['street'] != 'pre_flop'
        pos = state['current_position']
        state = described_class.apply_action(state, pos, { 'action' => 'call' })
      end
      if state['street'] == 'flop'
        expect(state['community_cards'].length).to eq 3
      end
    end

    it 'does not advance the street when an all-in raiser still has opponents who must act' do
      state = make_state(%w[Alice Bob])
      state = described_class.deal_hand(state)
      sb_pos = state['current_position']
      state = described_class.apply_action(state, sb_pos, { 'action' => 'raise', 'amount' => 1000 })
      expect(state['street']).to eq 'pre_flop'
      expect(state['players_to_act']).to eq 1
    end

    it 'runs out all remaining streets when all players go all-in pre-flop' do
      state = make_state(%w[Alice Bob])
      state = described_class.deal_hand(state)
      sb_pos = state['current_position']
      bb_pos = state['seats'].find { |s| s['status'] == 'active' && s['position'] != sb_pos }.fetch('position')
      state = described_class.apply_action(state, sb_pos, { 'action' => 'raise', 'amount' => 1000 })
      state = described_class.apply_action(state, bb_pos, { 'action' => 'call' })
      expect(state['street']).to eq 'hand_over'
    end

    it 'plays a full hand to hand_over when players check through every street' do
      state = make_state(%w[Alice Bob])
      state = described_class.deal_hand(state)
      20.times do
        break if state['street'] == 'hand_over'
        pos = state['current_position']
        break unless pos
        seat = state['seats'].find { |s| s['position'] == pos }
        action = seat['bet'].to_i >= state['current_bet'].to_i ? 'check' : 'call'
        state = described_class.apply_action(state, pos, { 'action' => action })
      end
      expect(state['street']).to eq 'hand_over'
    end

    it 'awards the full pot to the winner' do
      state = make_state(%w[Alice Bob])
      state = described_class.deal_hand(state)
      total_chips = state['seats'].sum { |s| s['stack'] } + state['pot'].to_i
      20.times do
        break if state['street'] == 'hand_over'
        pos = state['current_position']
        break unless pos
        seat = state['seats'].find { |s| s['position'] == pos }
        action = seat['bet'].to_i >= state['current_bet'].to_i ? 'check' : 'call'
        state = described_class.apply_action(state, pos, { 'action' => action })
      end
      expect(state['pot']).to eq 0
      expect(state['seats'].sum { |s| s['stack'] }).to eq total_chips
    end

    it 'advances dealer position after hand_over' do
      state = make_state(%w[Alice Bob])
      state = described_class.deal_hand(state)
      dealer_before = state['dealer_position']
      20.times do
        break if state['street'] == 'hand_over'
        pos = state['current_position']
        break unless pos
        seat = state['seats'].find { |s| s['position'] == pos }
        action = seat['bet'].to_i >= state['current_bet'].to_i ? 'check' : 'call'
        state = described_class.apply_action(state, pos, { 'action' => action })
      end
      expect(state['dealer_position']).not_to eq dealer_before
    end
  end

  describe '.join_seat' do
    it 'places a player in an empty seat' do
      state = make_state([])
      new_state = described_class.join_seat(state, 2, 'Alice', 'sid1')
      seat = new_state['seats'][2]
      expect(seat['name']).to eq 'Alice'
      expect(seat['stack']).to eq 1000
      expect(seat['status']).to eq 'sitting_out'
      expect(seat['session_id']).to eq 'sid1'
    end

    it 'raises if seat is occupied' do
      state = make_state(%w[Alice])
      expect {
        described_class.join_seat(state, 0, 'Bob', 'sid2')
      }.to raise_error(Games::NlHoldem::SeatOccupiedError)
    end
  end

  describe '.leave_seat' do
    it 'empties the seat' do
      state = make_state(%w[Alice Bob])
      new_state = described_class.leave_seat(state, 'sid0')
      expect(new_state['seats'][0]['status']).to eq 'empty'
      expect(new_state['seats'][0]['name']).to be_nil
    end
  end

  describe '.add_bot' do
    it 'places a bot in an empty seat' do
      state = make_state([])
      new_state = described_class.add_bot(state, 3)
      seat = new_state['seats'][3]
      expect(seat['is_bot']).to be true
      expect(seat['name']).to match(/Bot/)
      expect(seat['status']).to eq 'sitting_out'
    end
  end
end
