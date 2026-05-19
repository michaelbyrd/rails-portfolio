class NextHandJob < ApplicationJob
  queue_as :default

  def perform(table_slug)
    table = Table.find_by(slug: table_slug)
    return unless table
    return unless table.state['street'] == 'hand_over'

    can_play = table.state['seats'].count { |s| s['status'] != 'empty' && s['stack'].to_i > 0 }

    if can_play >= 2
      table.start_hand!
      current_pos = table.state['current_position']
      if current_pos
        current_seat = table.state['seats'].find { |s| s['position'] == current_pos }
        BotActionJob.set(wait: 1.5.seconds).perform_later(table_slug, current_pos) if current_seat&.fetch('is_bot', false)
      end
    else
      new_state = table.state.merge(
        'status' => 'waiting', 'street' => nil,
        'current_position' => nil, 'current_bet' => 0, 'pot' => 0
      )
      table.update!(state: new_state)
    end

    ActionCable.server.broadcast(
      "card_room_#{table_slug}",
      { type: 'state_update', state: table.state }
    )
  end
end
