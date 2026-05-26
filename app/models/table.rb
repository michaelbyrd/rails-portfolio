class Table < ApplicationRecord
  before_create :generate_slug
  after_initialize :initialize_state, if: :new_record?

  def engine
    Games::NlHoldem
  end

  def join_seat(position, name, session_id)
    new_state = engine.join_seat(state, position, name, session_id)
    update!(state: new_state)
    start_hand! if should_start?
  end

  def leave_seat(session_id)
    new_state = engine.leave_seat(state, session_id)
    update!(state: new_state)
  end

  def apply_action(position, action_data)
    new_state = engine.apply_action(state, position, action_data)
    update!(state: new_state)
  end

  def add_bot(position)
    new_state = engine.add_bot(state, position)
    update!(state: new_state)
    start_hand! if should_start?
  end

  def reset!
    self.state = {
      'status' => 'waiting', 'street' => nil, 'hand_number' => 0,
      'dealer_position' => 0, 'current_position' => nil, 'current_bet' => 0,
      'min_raise' => 20, 'pot' => 0, 'players_to_act' => 0,
      'community_cards' => [], 'deck' => [], 'last_action' => nil,
      'seats' => Array.new(max_seats) { |i|
        { 'position' => i, 'name' => nil, 'stack' => 0, 'bet' => 0,
          'hole_cards' => [], 'status' => 'empty', 'is_bot' => false, 'session_id' => nil }
      }
    }
    save!
  end

  def start_hand!
    new_state = engine.deal_hand(state)
    update!(state: new_state)
  end

  def broadcast_to_all
    ActionCable.server.broadcast(
      "card_room_#{slug}",
      { type: 'state_update', state: masked_state }
    )
    state['seats'].each do |seat|
      next if seat['session_id'].nil? || seat['is_bot']
      ActionCable.server.broadcast(
        "card_room_#{slug}_#{seat['session_id']}",
        { type: 'state_update', state: state_for(seat['session_id']) }
      )
    end
  end

  def masked_state
    state_for(nil)
  end

  def state_for(session_id)
    s = state.deep_dup
    at_showdown = s['street'] == 'hand_over' &&
      s['seats'].count { |st| %w[active all_in].include?(st['status']) } > 1
    s['seats'] = s['seats'].map do |seat|
      if seat['session_id'] == session_id
        seat
      elsif at_showdown && %w[active all_in].include?(seat['status'])
        seat
      else
        seat.merge('hole_cards' => seat['hole_cards'].any? ? ['??', '??'] : [])
      end
    end
    s
  end

  private

  def should_start?
    reload
    seated = state['seats'].reject { |s| s['status'] == 'empty' }
    seated.count >= 2 && state['status'] == 'waiting'
  end

  def initialize_state
    return if state.present? && state['seats'].present?
    self.state = {
      'status'           => 'waiting',
      'street'           => nil,
      'hand_number'      => 0,
      'dealer_position'  => 0,
      'current_position' => nil,
      'current_bet'      => 0,
      'min_raise'        => 20,
      'pot'              => 0,
      'players_to_act'   => 0,
      'community_cards'  => [],
      'deck'             => [],
      'last_action'      => nil,
      'seats'            => Array.new(max_seats) { |i|
        { 'position' => i, 'name' => nil, 'stack' => 0, 'bet' => 0,
          'hole_cards' => [], 'status' => 'empty', 'is_bot' => false, 'session_id' => nil }
      }
    }
  end

  def generate_slug
    loop do
      self.slug = SecureRandom.alphanumeric(8).downcase
      break unless Table.exists?(slug: slug)
    end
  end
end
