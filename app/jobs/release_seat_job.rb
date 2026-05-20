class ReleaseSeatJob < ApplicationJob
  queue_as :default

  def perform(table_slug, session_id, enqueued_at = nil)
    table = Table.find_by(slug: table_slug)
    unless table
      Rails.logger.warn "[ReleaseSeat] table not found slug=#{table_slug}"
      return
    end

    seat = table.state['seats'].find { |s| s['session_id'] == session_id }
    if seat.nil? || seat['status'] == 'empty'
      Rails.logger.info "[ReleaseSeat] SKIP seat already empty slug=#{table_slug} session=#{session_id}"
      return
    end

    if enqueued_at && seat['joined_at'].to_f > enqueued_at.to_f
      Rails.logger.info "[ReleaseSeat] SKIP player rejoined slug=#{table_slug} session=#{session_id}"
      return
    end

    state = table.state
    Rails.logger.info "[ReleaseSeat] START slug=#{table_slug} session=#{session_id} seat_pos=#{seat['position']} seat_status=#{seat['status']} game_status=#{state['status']} current_pos=#{state['current_position']}"

    if state['status'] == 'playing' && %w[active all_in].include?(seat['status'])
      if seat['status'] == 'active' && state['current_position'] == seat['position']
        Rails.logger.info "[ReleaseSeat] AUTO-FOLD slug=#{table_slug} pos=#{seat['position']}"
        table.apply_action(seat['position'], { 'action' => 'fold' })
        table.reload

        if table.state['street'] == 'hand_over'
          Rails.logger.info "[ReleaseSeat] ENQUEUE NextHandJob slug=#{table_slug}"
          NextHandJob.set(wait: 3.seconds).perform_later(table_slug)
        else
          current_pos = table.state['current_position']
          if current_pos
            current_seat = table.state['seats'].find { |s| s['position'] == current_pos }
            if current_seat&.fetch('is_bot', false)
              Rails.logger.info "[ReleaseSeat] ENQUEUE BotActionJob slug=#{table_slug} pos=#{current_pos}"
              BotActionJob.set(wait: 1.5.seconds).perform_later(table_slug, current_pos)
            end
          end
        end

        ActionCable.server.broadcast("card_room_#{table_slug}",
          { type: 'state_update', state: table.masked_state })
      else
        Rails.logger.info "[ReleaseSeat] DEFER not their turn slug=#{table_slug} pos=#{seat['position']} current_pos=#{state['current_position']}"
        ReleaseSeatJob.set(wait: 30.seconds).perform_later(table_slug, session_id, enqueued_at || Time.current.to_f)
        return
      end
    end

    table.reload
    seat = table.state['seats'].find { |s| s['session_id'] == session_id }
    if seat.nil? || seat['status'] == 'empty'
      Rails.logger.info "[ReleaseSeat] seat already cleared slug=#{table_slug} session=#{session_id}"
      return
    end

    Rails.logger.info "[ReleaseSeat] REMOVE seat slug=#{table_slug} pos=#{seat['position']}"
    table.leave_seat(session_id)
    ActionCable.server.broadcast("card_room_#{table_slug}",
      { type: 'state_update', state: table.state })
  end
end
