module Games
  class Deck
    RANKS = %w[2 3 4 5 6 7 8 9 T J Q K A].freeze
    SUITS = %w[h d s c].freeze

    def initialize(cards = nil)
      @cards = cards || RANKS.product(SUITS).map { |r, s| "#{r}#{s}" }.shuffle
    end

    def deal(n = 1)
      @cards.pop(n)
    end

    def remaining
      @cards.length
    end

    def cards
      @cards.dup
    end

    def to_a
      @cards.dup
    end
  end
end
