class NextHandJob < ApplicationJob
  queue_as :default

  def perform(table_slug)
    table = Table.find_by(slug: table_slug)
    unless table
      Rails.logger.warn "[NextHandJob] table not found slug=#{table_slug}"
      return
    end

    street = table.state['street']
    unless street == 'hand_over'
      Rails.logger.info "[NextHandJob] SKIP not hand_over slug=#{table_slug} street=#{street}"
      return
    end

    can_play = table.state['seats'].count { |s| s['status'] != 'empty' && s['stack'].to_i > 0 }
    Rails.logger.info "[NextHandJob] START slug=#{table_slug} can_play=#{can_play}"

    if can_play >= 2
      table.start_hand!
      current_pos = table.state['current_position']
      Rails.logger.info "[NextHandJob] DEALT slug=#{table_slug} current_pos=#{current_pos} hand=#{table.state['hand_number']}"
      if current_pos
        current_seat = table.state['seats'].find { |s| s['position'] == current_pos }
        if current_seat&.fetch('is_bot', false)
          Rails.logger.info "[NextHandJob] ENQUEUE BotActionJob slug=#{table_slug} pos=#{current_pos}"
          BotActionJob.set(wait: 1.5.seconds).perform_later(table_slug, current_pos)
        end
      end
    else
      Rails.logger.info "[NextHandJob] WAITING not enough players slug=#{table_slug}"
      new_state = table.state.merge(
        'status' => 'waiting', 'street' => nil,
        'current_position' => nil, 'current_bet' => 0, 'pot' => 0
      )
      table.update!(state: new_state)
    end

    table.broadcast_to_all
  end
end
