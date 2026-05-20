require 'rails_helper'

RSpec.describe CardRoomChannel, type: :channel do
  let(:table) { create(:table) }
  let(:session_id) { 'test_session_123' }

  describe '#subscribed' do
    it 'streams from the public table stream' do
      subscribe slug: table.slug, session_id: session_id
      expect(subscription).to be_confirmed
      expect(subscription).to have_stream_from("card_room_#{table.slug}")
    end

    it 'streams from the personal session stream' do
      subscribe slug: table.slug, session_id: session_id
      expect(subscription).to have_stream_from("card_room_#{table.slug}_#{session_id}")
    end

    it 'rejects when table slug does not exist' do
      subscribe slug: 'nosuchslug', session_id: session_id
      expect(subscription).to be_rejected
    end
  end

  describe '#receive — public broadcast uses masked state' do
    before do
      table.join_seat(0, 'Alice', session_id)
      table.join_seat(1, 'Bob', 'other_session')
      table.reload
      subscribe slug: table.slug, session_id: session_id
    end

    it 'does not include real hole cards in the public stream broadcast' do
      pos = table.state['current_position']
      seat = table.state['seats'].find { |s| s['position'] == pos }
      action = seat['bet'].to_i >= table.state['current_bet'].to_i ? 'check' : 'call'

      expect {
        perform :receive, { 'type' => 'action', 'position' => pos, 'move' => action }
      }.to have_broadcasted_to("card_room_#{table.slug}").with(
        a_hash_including(
          'type' => 'state_update',
          'state' => a_hash_including(
            'seats' => satisfy('all occupied seats have masked or empty hole cards') { |seats|
              seats.reject { |s| s['status'] == 'empty' }.all? { |s|
                s['hole_cards'] == %w[?? ??] || s['hole_cards'] == []
              }
            }
          )
        )
      )
    end
  end
end
