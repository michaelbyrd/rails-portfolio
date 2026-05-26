class BotActionJob < ApplicationJob
  queue_as :default

  def perform(table_slug, position)
    table = Table.find_by(slug: table_slug)
    unless table
      Rails.logger.warn "[BotJob] table not found slug=#{table_slug}"
      return
    end

    action_taken = nil

    table.with_lock do
      state = table.state
      unless state['status'] == 'playing'
        Rails.logger.info "[BotJob] SKIP not playing slug=#{table_slug} status=#{state['status']}"
        next
      end
      unless state['current_position'] == position
        Rails.logger.info "[BotJob] SKIP pos mismatch slug=#{table_slug} expected=#{position} actual=#{state['current_position']} street=#{state['street']}"
        next
      end
      action_taken = Games::Bot.decide(state, position)
      Rails.logger.info "[BotJob] ACT slug=#{table_slug} pos=#{position} action=#{action_taken.inspect} street=#{state['street']}"
      table.apply_action(position, action_taken)
    end

    return unless action_taken

    table.reload
    street = table.state['street']
    next_pos = table.state['current_position']
    Rails.logger.info "[BotJob] DONE slug=#{table_slug} pos=#{position} -> street=#{street} next_pos=#{next_pos}"

    table.broadcast_to_all

    if street == 'hand_over'
      Rails.logger.info "[BotJob] ENQUEUE NextHandJob slug=#{table_slug}"
      NextHandJob.set(wait: 3.seconds).perform_later(table_slug)
      return
    end

    return unless next_pos && table.state['status'] == 'playing'

    next_seat = table.state['seats'].find { |s| s['position'] == next_pos }
    if next_seat&.fetch('is_bot', false)
      Rails.logger.info "[BotJob] CHAIN -> slug=#{table_slug} next_pos=#{next_pos}"
      BotActionJob.set(wait: 0.5.seconds).perform_later(table_slug, next_pos)
    end
  rescue Games::NlHoldem::InvalidActionError => e
    Rails.logger.warn "[BotJob] RACE_SKIP slug=#{table_slug} pos=#{position} #{e.message}"
  rescue => e
    Rails.logger.error "[BotJob] ERROR slug=#{table_slug} pos=#{position} #{e.class}: #{e.message}\n#{e.backtrace.first(3).join("\n")}"
    raise
  end
end
