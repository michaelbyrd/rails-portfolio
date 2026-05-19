module Games
  class Bot
    PREMIUM = [%w[A A], %w[K K], %w[Q Q], %w[J J]].freeze
    STRONG  = [%w[A K], %w[A Q], %w[T T], %w[9 9], %w[8 8]].freeze

    def self.decide(state, position)
      seat        = state['seats'].find { |s| s['position'] == position }
      strength    = hand_strength(seat['hole_cards'], state['community_cards'], state['street'])
      current_bet = state['current_bet'].to_i
      seat_bet    = seat['bet'].to_i
      to_call     = current_bet - seat_bet
      min_raise   = current_bet + state['min_raise'].to_i
      stack       = seat['stack'].to_i

      case strength
      when :premium
        raise_amount = [min_raise * 3, stack + seat_bet].min
        { 'action' => 'raise', 'amount' => raise_amount }
      when :strong
        raise_amount = [min_raise * 2, stack + seat_bet].min
        { 'action' => 'raise', 'amount' => raise_amount }
      when :medium
        to_call > 0 ? { 'action' => 'call' } : { 'action' => 'check' }
      else
        if rand < 0.15 && stack > 0
          raise_amount = [min_raise, stack + seat_bet].min
          { 'action' => 'raise', 'amount' => raise_amount }
        elsif to_call == 0
          { 'action' => 'check' }
        else
          { 'action' => 'fold' }
        end
      end
    end

    def self.hand_strength(hole_cards, community_cards, street)
      if street == 'pre_flop'
        preflop_strength(hole_cards)
      else
        postflop_strength(hole_cards, community_cards)
      end
    end

    def self.preflop_strength(hole_cards)
      ranks = hole_cards.map { |c| c[0] }.sort.reverse
      return :premium if PREMIUM.include?(ranks)
      return :strong  if STRONG.include?(ranks)

      r1, r2 = hole_cards.map { |c| c[0] }
      suited  = hole_cards[0][1] == hole_cards[1][1]
      v1      = Games::HandEvaluator::RANK_VALUES[r1].to_i
      v2      = Games::HandEvaluator::RANK_VALUES[r2].to_i
      gap     = (v1 - v2).abs

      return :medium if suited && gap <= 2
      return :medium if v1 >= 10 && v2 >= 10
      :weak
    end

    def self.postflop_strength(hole_cards, community_cards)
      score = Games::HandEvaluator.best_hand(hole_cards + community_cards)
      case score[0]
      when 5..8 then :premium
      when 3..4 then :strong
      when 2    then :medium
      when 1    then rand < 0.5 ? :medium : :weak
      else :weak
      end
    end

    private_class_method :hand_strength, :preflop_strength, :postflop_strength
  end
end
