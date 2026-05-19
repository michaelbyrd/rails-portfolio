require 'rails_helper'

RSpec.describe Games::HandEvaluator do
  describe '.score' do
    it 'scores a straight flush' do
      expect(described_class.score(%w[9h Th Jh Qh Kh])).to eq([8, 13])
    end

    it 'scores a royal flush' do
      expect(described_class.score(%w[Ah Kh Qh Jh Th])).to eq([8, 14])
    end

    it 'scores four of a kind' do
      expect(described_class.score(%w[Ah As Ad Ac Kh])).to eq([7, 14, 13])
    end

    it 'scores a full house' do
      expect(described_class.score(%w[Ah As Ad Kh Ks])).to eq([6, 14, 13])
    end

    it 'scores a flush' do
      expect(described_class.score(%w[2h 5h 7h Jh Kh])).to eq([5, 13, 11, 7, 5, 2])
    end

    it 'scores a straight' do
      expect(described_class.score(%w[9d Th Js Qc Kh])).to eq([4, 13])
    end

    it 'scores a wheel straight (A-2-3-4-5)' do
      expect(described_class.score(%w[Ah 2d 3s 4c 5h])).to eq([4, 5])
    end

    it 'scores three of a kind' do
      expect(described_class.score(%w[Ah As Ad Kh 2c])).to eq([3, 14, 13, 2])
    end

    it 'scores two pair' do
      expect(described_class.score(%w[Ah As Kh Ks 2d])).to eq([2, 14, 13, 2])
    end

    it 'scores one pair' do
      expect(described_class.score(%w[Ah As Kh Qd 2c])).to eq([1, 14, 13, 12, 2])
    end

    it 'scores high card' do
      expect(described_class.score(%w[Ah Kd Qh Jc 9s])).to eq([0, 14, 13, 12, 11, 9])
    end

    it 'ranks higher flush over lower flush' do
      high = described_class.score(%w[Ah Kh Qh Jh 9h])
      low  = described_class.score(%w[Kh Qh Jh 9h 8h])
      expect(high <=> low).to eq 1
    end

    it 'does not confuse a straight flush with a plain flush' do
      expect(described_class.score(%w[9h Th Jh Qh Kh])[0]).to eq 8
    end
  end

  describe '.best_hand' do
    it 'selects the best 5 from 7 cards' do
      # Three kings + pocket aces → full house (kings full of aces)
      cards = %w[Ah As Kd Kh Ks 2c 3d]
      result = described_class.best_hand(cards)
      expect(result[0]).to eq 6
      expect(result[1]).to eq 13
      expect(result[2]).to eq 14
    end

    it 'ignores irrelevant cards' do
      cards = %w[2h 2d 3c 4s 5h 8c 9d]
      result = described_class.best_hand(cards)
      expect(result[0]).to eq 1
    end
  end
end
