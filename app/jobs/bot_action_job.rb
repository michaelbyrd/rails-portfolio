class BotActionJob < ApplicationJob
  queue_as :default

  def perform(table_slug, position)
    table = Table.find_by(slug: table_slug)
    return unless table
    return unless table.state['current_position'] == position

    action = Games::Bot.decide(table.state, position)
    table.apply_action(position, action)

    ActionCable.server.broadcast(
      "card_room_#{table_slug}",
      { type: 'state_update', state: table.state }
    )

    table.reload
    next_pos = table.state['current_position']
    return unless next_pos && table.state['status'] == 'playing'

    next_seat = table.state['seats'].find { |s| s['position'] == next_pos }
    if next_seat&.fetch('is_bot', false)
      BotActionJob.set(wait: 1.5.seconds).perform_later(table_slug, next_pos)
    end
  end
end
