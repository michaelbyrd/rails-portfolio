module Games
  class HandEvaluator
    RANK_VALUES = {
      '2' => 2, '3' => 3, '4' => 4, '5' => 5, '6' => 6,
      '7' => 7, '8' => 8, '9' => 9, 'T' => 10, 'J' => 11,
      'Q' => 12, 'K' => 13, 'A' => 14
    }.freeze

    def self.best_hand(cards)
      cards.combination(5).map { |five| score(five) }.max
    end

    def self.score(five_cards)
      ranks  = five_cards.map { |c| RANK_VALUES[c[0]] }.sort.reverse
      suits  = five_cards.map { |c| c[1] }
      flush  = suits.uniq.size == 1
      str_hi = straight_high(ranks)
      groups = ranks.tally.sort_by { |rank, count| [-count, -rank] }
      counts = groups.map(&:last)
      ranked = groups.map(&:first)

      if flush && str_hi
        [8, str_hi]
      elsif counts[0] == 4
        [7, ranked[0], ranked[1]]
      elsif counts[0] == 3 && counts[1] == 2
        [6, ranked[0], ranked[1]]
      elsif flush
        [5, *ranks]
      elsif str_hi
        [4, str_hi]
      elsif counts[0] == 3
        [3, ranked[0], ranked[1], ranked[2]]
      elsif counts[0] == 2 && counts[1] == 2
        [2, ranked[0], ranked[1], ranked[2]]
      elsif counts[0] == 2
        [1, ranked[0], ranked[1], ranked[2], ranked[3]]
      else
        [0, *ranks]
      end
    end

    def self.straight_high(desc_ranks)
      if desc_ranks[0] - desc_ranks[4] == 4 && desc_ranks.uniq.size == 5
        desc_ranks[0]
      elsif desc_ranks == [14, 5, 4, 3, 2]
        5
      end
    end
  end
end
