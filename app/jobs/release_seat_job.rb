class ReleaseSeatJob < ApplicationJob
  queue_as :default

  def perform(table_slug, session_id, enqueued_at = nil)
    table = Table.find_by(slug: table_slug)
    return unless table

    seat = table.state['seats'].find { |s| s['session_id'] == session_id }
    return if seat.nil? || seat['status'] == 'empty'

    # Skip if the player rejoined after this job was enqueued (same session_id, new seat)
    return if enqueued_at && seat['joined_at'].to_f > enqueued_at.to_f

    state = table.state

    if state['status'] == 'playing' && %w[active all_in].include?(seat['status'])
      if seat['status'] == 'active' && state['current_position'] == seat['position']
        # It's this player's turn — auto-fold so the game can continue
        table.apply_action(seat['position'], { 'action' => 'fold' })
        table.reload

        if table.state['street'] == 'hand_over'
          NextHandJob.set(wait: 3.seconds).perform_later(table_slug)
        else
          current_pos = table.state['current_position']
          if current_pos
            current_seat = table.state['seats'].find { |s| s['position'] == current_pos }
            if current_seat&.fetch('is_bot', false)
              BotActionJob.set(wait: 1.5.seconds).perform_later(table_slug, current_pos)
            end
          end
        end

        ActionCable.server.broadcast("card_room_#{table_slug}",
          { type: 'state_update', state: table.state })
      else
        # Not their turn or they're all-in — re-check after the next action
        ReleaseSeatJob.set(wait: 30.seconds).perform_later(table_slug, session_id, enqueued_at || Time.current.to_f)
        return
      end
    end

    # Remove the seat after any fold has been processed
    table.reload
    seat = table.state['seats'].find { |s| s['session_id'] == session_id }
    return if seat.nil? || seat['status'] == 'empty'

    table.leave_seat(session_id)
    ActionCable.server.broadcast("card_room_#{table_slug}",
      { type: 'state_update', state: table.state })
  end
end
