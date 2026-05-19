module Games
  class NlHoldem
    class SeatOccupiedError < StandardError; end
    class InvalidActionError < StandardError; end

    SMALL_BLIND    = 10
    BIG_BLIND      = 20
    STARTING_STACK = 1000

    # ── Seat management ────────────────────────────────────────────────────────

    def self.join_seat(state, position, name, session_id)
      s = state.deep_dup
      seat = find_seat(s, position)
      raise SeatOccupiedError, "Seat #{position} is occupied" unless seat['status'] == 'empty'
      seat.merge!(
        'name' => name, 'stack' => STARTING_STACK, 'bet' => 0,
        'hole_cards' => [], 'status' => 'sitting_out',
        'is_bot' => false, 'session_id' => session_id,
        'joined_at' => Time.current.to_f
      )
      s
    end

    def self.leave_seat(state, session_id)
      s = state.deep_dup
      seat = s['seats'].find { |st| st['session_id'] == session_id }
      return s unless seat
      seat.merge!(
        'name' => nil, 'stack' => 0, 'bet' => 0, 'hole_cards' => [],
        'status' => 'empty', 'is_bot' => false, 'session_id' => nil
      )
      s
    end

    def self.add_bot(state, position)
      s = state.deep_dup
      seat = find_seat(s, position)
      raise SeatOccupiedError, "Seat #{position} is occupied" unless seat['status'] == 'empty'
      bot_number = s['seats'].count { |st| st['is_bot'] } + 1
      seat.merge!(
        'name' => "Bot #{bot_number}", 'stack' => STARTING_STACK, 'bet' => 0,
        'hole_cards' => [], 'status' => 'sitting_out',
        'is_bot' => true, 'session_id' => "bot_#{SecureRandom.hex(4)}"
      )
      s
    end

    # ── Deal hand ──────────────────────────────────────────────────────────────

    def self.deal_hand(state)
      s = state.deep_dup
      deck = Games::Deck.new

      # Reset for new hand: bust out 0-stack players, activate everyone else
      s['seats'].each do |st|
        next if st['status'] == 'empty'
        if st['stack'].to_i == 0
          st.merge!('status' => 'empty', 'name' => nil, 'session_id' => nil,
                    'is_bot' => false, 'hole_cards' => [], 'bet' => 0)
        else
          st['status'] = 'active'
        end
      end

      active_positions = active_seat_positions(s)
      dealer  = s['dealer_position']
      sb_pos  = next_position(active_positions, dealer)
      bb_pos  = next_position(active_positions, sb_pos)
      utg_pos = next_position(active_positions, bb_pos)

      s['seats'].each do |seat|
        next if seat['status'] == 'empty'
        seat['bet'] = 0
        seat['hole_cards'] = []
      end

      post_blind(s, sb_pos, SMALL_BLIND)
      post_blind(s, bb_pos, BIG_BLIND)

      deal_order = rotate_after(active_positions, dealer)
      deal_order.each { |pos| find_seat(s, pos)['hole_cards'] = deck.deal(2) }

      s.merge!(
        'status'           => 'playing',
        'street'           => 'pre_flop',
        'hand_number'      => s['hand_number'].to_i + 1,
        'dealer_position'  => dealer,
        'current_position' => utg_pos,
        'current_bet'      => BIG_BLIND,
        'min_raise'        => BIG_BLIND,
        'pot'              => SMALL_BLIND + BIG_BLIND,
        'community_cards'  => [],
        'deck'             => deck.to_a,
        'last_action'      => nil,
        'players_to_act'   => active_positions.length
      )
      s
    end

    # ── Apply action ───────────────────────────────────────────────────────────

    def self.apply_action(state, position, action_data)
      s = state.deep_dup
      seat = find_seat(s, position)
      raise InvalidActionError, "Not this player's turn" unless s['current_position'] == position
      raise InvalidActionError, "Player is not active" unless seat['status'] == 'active'

      case action_data['action']
      when 'fold'
        seat['status'] = 'folded'
        s['last_action'] = { 'player' => seat['name'], 'action' => 'fold' }
        s['players_to_act'] = [s['players_to_act'].to_i - 1, 0].max
        return award_pot(s, active_seats(s).first['position']) if active_seats(s).one?

      when 'check'
        raise InvalidActionError, "Cannot check — current bet is #{s['current_bet']}" unless seat['bet'].to_i >= s['current_bet'].to_i
        s['last_action'] = { 'player' => seat['name'], 'action' => 'check' }
        s['players_to_act'] = [s['players_to_act'].to_i - 1, 0].max

      when 'call'
        amount = [s['current_bet'].to_i - seat['bet'].to_i, seat['stack'].to_i].min
        seat['stack']  -= amount
        seat['bet']     = seat['bet'].to_i + amount
        s['pot']       += amount
        seat['status']  = 'all_in' if seat['stack'] == 0
        s['last_action'] = { 'player' => seat['name'], 'action' => 'call', 'amount' => amount }
        s['players_to_act'] = [s['players_to_act'].to_i - 1, 0].max

      when 'raise'
        raise_to     = action_data['amount'].to_i
        min_total    = s['current_bet'].to_i + s['min_raise'].to_i
        all_in_total = seat['bet'].to_i + seat['stack'].to_i
        raise InvalidActionError, "Raise must be at least #{min_total}" unless raise_to >= min_total || raise_to == all_in_total
        raise_to     = [raise_to, all_in_total].min
        increment    = raise_to - s['current_bet'].to_i
        amount       = raise_to - seat['bet'].to_i
        seat['stack'] -= amount
        seat['bet']    = seat['bet'].to_i + amount
        s['pot']      += amount
        s['current_bet'] = raise_to
        s['min_raise']   = [increment, BIG_BLIND].max
        seat['status']   = 'all_in' if seat['stack'] == 0
        s['last_action'] = { 'player' => seat['name'], 'action' => 'raise', 'amount' => amount }
        active_count     = active_seats(s).count { |st| st['status'] == 'active' }
        s['players_to_act'] = active_count - 1
      end

      if s['players_to_act'].to_i <= 0
        advance_street(s)
      else
        s['current_position'] = next_to_act(s, position)
        s
      end
    end

    # ── Private helpers ────────────────────────────────────────────────────────

    def self.advance_street(state)
      s = state.deep_dup
      deck_cards = s['deck'].dup

      case s['street']
      when 'pre_flop'
        s['community_cards'] = deck_cards.pop(3)
        s['street'] = 'flop'
      when 'flop'
        s['community_cards'] = s['community_cards'] + deck_cards.pop(1)
        s['street'] = 'turn'
      when 'turn'
        s['community_cards'] = s['community_cards'] + deck_cards.pop(1)
        s['street'] = 'river'
      when 'river'
        return resolve_showdown(s)
      end

      s['deck'] = deck_cards
      s['current_bet'] = 0
      s['min_raise']   = BIG_BLIND
      s['seats'].each { |st| st['bet'] = 0 if st['status'] != 'empty' }

      first_pos = first_to_act_post_flop(s)
      s['current_position'] = first_pos
      s['players_to_act']   = active_seats(s).count { |st| st['status'] == 'active' }
      s
    end

    def self.resolve_showdown(state)
      s = state.deep_dup
      s['street'] = 'showdown'
      contenders = active_seats(s)

      winner = contenders.max_by do |seat|
        Games::HandEvaluator.best_hand(seat['hole_cards'] + s['community_cards'])
      end

      winner['stack'] += s['pot']
      s['pot']         = 0
      s['last_action'] = { 'player' => winner['name'], 'action' => 'wins' }
      s['street']      = 'hand_over'

      next_dealer = next_position(active_seat_positions(s), s['dealer_position'])
      s['dealer_position'] = next_dealer
      s
    end

    def self.award_pot(state, winner_position)
      s = state.deep_dup
      winner = find_seat(s, winner_position)
      winner['stack'] += s['pot']
      s['pot']         = 0
      s['last_action'] = { 'player' => winner['name'], 'action' => 'wins' }
      s['street']      = 'hand_over'
      next_dealer = next_position(active_seat_positions(s), s['dealer_position'])
      s['dealer_position'] = next_dealer
      s
    end

    def self.post_blind(state, position, amount)
      seat = find_seat(state, position)
      actual = [amount, seat['stack']].min
      seat['stack'] -= actual
      seat['bet']    = actual
      state['pot']  += actual
      seat['status'] = 'all_in' if seat['stack'] == 0
    end

    def self.find_seat(state, position)
      state['seats'].find { |s| s['position'] == position } ||
        raise(InvalidActionError, "Seat #{position} not found")
    end

    def self.active_seats(state)
      state['seats'].reject { |s| %w[empty folded].include?(s['status']) }
    end

    def self.active_seat_positions(state)
      active_seats(state).map { |s| s['position'] }.sort
    end

    def self.next_position(positions, current)
      idx = positions.index(current) || -1
      positions[(idx + 1) % positions.length]
    end

    def self.rotate_after(positions, current)
      idx = positions.index(current) || -1
      positions[(idx + 1)..] + positions[..idx]
    end

    def self.next_to_act(state, after_position)
      positions = active_seats(state).select { |s| s['status'] == 'active' }.map { |s| s['position'] }.sort
      rotate_after(positions, after_position).first
    end

    def self.first_to_act_post_flop(state)
      positions = active_seats(state).select { |s| s['status'] == 'active' }.map { |s| s['position'] }.sort
      dealer = state['dealer_position']
      rotate_after(positions, dealer).first
    end

    private_class_method :advance_street, :resolve_showdown, :award_pot, :post_blind,
                         :find_seat, :active_seats, :active_seat_positions,
                         :next_position, :rotate_after, :next_to_act, :first_to_act_post_flop
  end
end
