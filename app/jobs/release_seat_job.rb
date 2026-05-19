class ReleaseSeatJob < ApplicationJob
  queue_as :default

  def perform(table_slug, session_id)
    table = Table.find_by(slug: table_slug)
    return unless table

    seat = table.state['seats'].find { |s| s['session_id'] == session_id }
    return if seat.nil? || seat['status'] == 'empty'

    table.leave_seat(session_id)
    ActionCable.server.broadcast(
      "card_room_#{table_slug}",
      { type: 'state_update', state: table.state }
    )
  end
end
