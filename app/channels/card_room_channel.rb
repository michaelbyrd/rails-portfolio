class CardRoomChannel < ApplicationCable::Channel
  def subscribed
    table = Table.find_by(slug: params[:slug])
    return reject unless table

    @table_slug = params[:slug]
    @session_id = params[:session_id]
    stream_from "card_room_#{@table_slug}"

    transmit({ type: 'state_update', state: table.state_for(@session_id) })
  end

  def unsubscribed
    return unless @table_slug && @session_id
    ReleaseSeatJob.set(wait: 30.seconds).perform_later(@table_slug, @session_id)
  end

  def receive(data)
    table = Table.find_by!(slug: @table_slug)

    case data['type']
    when 'join_seat'
      table.join_seat(data['position'].to_i, data['name'], @session_id)
    when 'leave_seat'
      table.leave_seat(@session_id)
    when 'action'
      table.apply_action(data['position'].to_i, data)
      maybe_trigger_bot(table)
    when 'add_bot'
      table.add_bot(data['position'].to_i)
      maybe_trigger_bot(table)
    end

    ActionCable.server.broadcast(
      "card_room_#{@table_slug}",
      { type: 'state_update', state: table.state }
    )
  end

  private

  def maybe_trigger_bot(table)
    table.reload
    return unless table.state['status'] == 'playing'

    current_pos = table.state['current_position']
    return unless current_pos

    current_seat = table.state['seats'].find { |s| s['position'] == current_pos }
    return unless current_seat&.fetch('is_bot', false)

    BotActionJob.set(wait: 1.5.seconds).perform_later(table.slug, current_pos)
  end
end
