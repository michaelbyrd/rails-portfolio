require 'rails_helper'

RSpec.describe CardRoomChannel, 'smoke test: 1 player vs 1 bot', type: :channel do
  let(:table) { create(:table) }
  let(:human_session) { 'human_session' }

  before do
    subscribe slug: table.slug, session_id: human_session
    perform :receive, { 'type' => 'join_seat', 'position' => 0, 'name' => 'Human' }
    perform :receive, { 'type' => 'add_bot', 'position' => 1 }
    table.reload
  end

  # Drives the current hand to completion by alternating bot (BotActionJob.perform_now)
  # and human (perform :receive) turns until street == 'hand_over'.
  def drive_to_hand_over
    50.times do
      table.reload
      break if table.state['street'] == 'hand_over'

      current_pos = table.state['current_position']
      break unless current_pos && table.state['status'] == 'playing'

      current_seat = table.state['seats'].find { |s| s['position'] == current_pos }

      if current_seat&.fetch('is_bot', false)
        BotActionJob.perform_now(table.slug, current_pos)
      else
        action = current_seat['bet'].to_i < table.state['current_bet'].to_i ? 'call' : 'check'
        perform :receive, { 'type' => 'action', 'position' => current_pos, 'move' => action }
      end
    end
    table.reload
  end

  def deal_next_hand
    NextHandJob.perform_now(table.slug)
    table.reload
  end

  it 'auto-starts with status playing and street pre_flop' do
    expect(table.state['status']).to eq 'playing'
    expect(table.state['street']).to eq 'pre_flop'
    expect(table.state['hand_number']).to eq 1
  end

  it 'deals 2 hole cards to both the human and the bot' do
    human_seat = table.state['seats'].find { |s| s['session_id'] == human_session }
    bot_seat   = table.state['seats'].find { |s| s['is_bot'] }
    expect(human_seat['hole_cards'].length).to eq 2
    expect(bot_seat['hole_cards'].length).to eq 2
    expect(human_seat['hole_cards']).not_to eq bot_seat['hole_cards']
  end

  it 'completes the hand with the pot awarded to a winner' do
    drive_to_hand_over
    expect(table.state['street']).to eq 'hand_over'
    expect(table.state['pot']).to eq 0
    expect(table.state['last_action']['action']).to eq 'wins'
  end

  it 'conserves total chip count across 2 complete hands' do
    initial_chips = table.state['seats'].sum { |s| s['stack'] } + table.state['pot'].to_i

    drive_to_hand_over
    deal_next_hand
    drive_to_hand_over

    final_chips = table.state['seats'].sum { |s| s['stack'] } + table.state['pot'].to_i
    expect(final_chips).to eq initial_chips
  end

  it 'advances the dealer button after the first hand' do
    dealer_before = table.state['dealer_position']
    drive_to_hand_over
    deal_next_hand
    expect(table.state['dealer_position']).not_to eq dealer_before
  end

  it 'broadcasts masked opponent cards on the public stream when a new hand is dealt' do
    drive_to_hand_over
    expect {
      deal_next_hand
    }.to have_broadcasted_to("card_room_#{table.slug}").with(
      a_hash_including(
        'type' => 'state_update',
        'state' => a_hash_including(
          'seats' => satisfy('no occupied seat exposes real hole cards') { |seats|
            seats.reject { |s| s['status'] == 'empty' }.all? { |s|
              s['hole_cards'] == %w[?? ??] || s['hole_cards'] == []
            }
          }
        )
      )
    )
  end

  it "sends the human's real hole cards to their personal stream when a new hand is dealt" do
    drive_to_hand_over
    expect {
      deal_next_hand
    }.to have_broadcasted_to("card_room_#{table.slug}_#{human_session}").with(
      a_hash_including(
        'type' => 'state_update',
        'state' => a_hash_including(
          'seats' => include(
            a_hash_including(
              'session_id' => human_session,
              'hole_cards' => satisfy('two non-masked cards') { |cards|
                cards.length == 2 && cards.none? { |c| c == '??' }
              }
            )
          )
        )
      )
    )
  end
end
