require 'rails_helper'

RSpec.describe Games::Deck do
  describe '#initialize' do
    it 'creates 52 unique cards' do
      deck = Games::Deck.new
      expect(deck.remaining).to eq 52
      expect(deck.cards.uniq.length).to eq 52
    end

    it 'contains all ranks and suits' do
      deck = Games::Deck.new
      expect(deck.cards).to include('Ah', 'Kd', '2s', 'Tc')
    end
  end

  describe '#deal' do
    it 'deals the requested number of cards' do
      deck = Games::Deck.new
      cards = deck.deal(2)
      expect(cards.length).to eq 2
      expect(deck.remaining).to eq 50
    end

    it 'deals 1 card by default' do
      deck = Games::Deck.new
      card = deck.deal
      expect(card.length).to eq 1
      expect(deck.remaining).to eq 51
    end

    it 'removes dealt cards from the deck' do
      deck = Games::Deck.new
      dealt = deck.deal(5)
      dealt.each { |c| expect(deck.cards).not_to include(c) }
    end
  end

  describe '#to_a' do
    it 'returns remaining cards as array' do
      deck = Games::Deck.new
      deck.deal(10)
      expect(deck.to_a.length).to eq 42
    end
  end
end
