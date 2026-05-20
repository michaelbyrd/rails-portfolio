require 'rails_helper'

RSpec.describe NextHandJob, type: :job do
  def hand_over_state(table)
    table.state.merge('street' => 'hand_over', 'current_position' => nil)
  end

  describe '#perform' do
    it 'deals a new hand when enough players have chips' do
      table = create(:table)
      table.join_seat(0, 'Alice', 'sid_alice')
      table.join_seat(1, 'Bob', 'sid_bob')
      table.reload
      table.update!(state: hand_over_state(table))
      described_class.perform_now(table.slug)
      expect(table.reload.state['street']).to eq 'pre_flop'
    end

    it 'broadcasts personalized state to each human player\'s personal stream' do
      table = create(:table)
      table.join_seat(0, 'Alice', 'sid_alice')
      table.join_seat(1, 'Bob', 'sid_bob')
      table.reload
      table.update!(state: hand_over_state(table))

      expect {
        described_class.perform_now(table.slug)
      }.to have_broadcasted_to("card_room_#{table.slug}_sid_alice")
        .and have_broadcasted_to("card_room_#{table.slug}_sid_bob")
    end

    it 'includes real hole cards in personalized broadcasts' do
      table = create(:table)
      table.join_seat(0, 'Alice', 'sid_alice')
      table.join_seat(1, 'Bob', 'sid_bob')
      table.reload
      table.update!(state: hand_over_state(table))
      described_class.perform_now(table.slug)
      table.reload
      alice_seat = table.state['seats'].find { |s| s['session_id'] == 'sid_alice' }
      real_cards = alice_seat['hole_cards']

      expect {
        # Re-run so we can capture the broadcast content
        table.update!(state: hand_over_state(table))
        described_class.perform_now(table.slug)
      }.to have_broadcasted_to("card_room_#{table.slug}_sid_alice").with(
        a_hash_including(
          'type' => 'state_update',
          'state' => a_hash_including(
            'seats' => include(
              a_hash_including('session_id' => 'sid_alice', 'hole_cards' => be_a(Array))
            )
          )
        )
      )
    end

    it 'skips when street is not hand_over' do
      table = create(:table)
      table.join_seat(0, 'Alice', 'sid_alice')
      table.join_seat(1, 'Bob', 'sid_bob')
      table.reload
      hand_number_before = table.state['hand_number']
      described_class.perform_now(table.slug)
      expect(table.reload.state['hand_number']).to eq hand_number_before
    end
  end
end
