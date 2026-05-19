require 'rails_helper'

RSpec.describe Table, type: :model do
  describe 'slug generation' do
    it 'generates a slug on create' do
      table = Table.create!(name: 'Table 1', game_type: 'nl_holdem')
      expect(table.slug).to match(/\A[a-z0-9]{8}\z/)
    end

    it 'generates unique slugs' do
      slugs = Array.new(3) { Table.create!(name: 'T', game_type: 'nl_holdem').slug }
      expect(slugs.uniq.length).to eq 3
    end
  end

  describe 'initial state' do
    it 'initializes with waiting status and empty seats' do
      table = Table.create!(name: 'Table 1', game_type: 'nl_holdem')
      expect(table.state['status']).to eq 'waiting'
      expect(table.state['seats'].length).to eq 6
      expect(table.state['seats'].all? { |s| s['status'] == 'empty' }).to be true
    end

    it 'respects max_seats for seat count' do
      table = Table.create!(name: 'T', game_type: 'nl_holdem', max_seats: 4)
      expect(table.state['seats'].length).to eq 4
    end
  end

  describe '#join_seat' do
    it 'seats a player' do
      table = create(:table)
      table.join_seat(0, 'Alice', 'sid1')
      expect(table.reload.state['seats'][0]['name']).to eq 'Alice'
    end

    it 'auto-starts when 2 players join' do
      table = create(:table)
      table.join_seat(0, 'Alice', 'sid1')
      table.join_seat(1, 'Bob', 'sid2')
      expect(table.reload.state['status']).to eq 'playing'
    end

    it 'does not auto-start with only 1 player' do
      table = create(:table)
      table.join_seat(0, 'Alice', 'sid1')
      expect(table.reload.state['status']).to eq 'waiting'
    end
  end

  describe '#apply_action' do
    it 'delegates to engine and persists result' do
      table = create(:table)
      table.join_seat(0, 'Alice', 'sid1')
      table.join_seat(1, 'Bob', 'sid2')
      table.reload
      pos = table.state['current_position']
      table.apply_action(pos, { 'action' => 'fold' })
      expect(table.reload.state['last_action']['action']).to eq 'wins'
    end
  end

  describe '#leave_seat' do
    it 'empties the seat by session_id' do
      table = create(:table)
      table.join_seat(0, 'Alice', 'sid1')
      table.leave_seat('sid1')
      expect(table.reload.state['seats'][0]['status']).to eq 'empty'
    end
  end

  describe '#add_bot' do
    it 'adds a bot to an empty seat' do
      table = create(:table)
      table.add_bot(2)
      expect(table.reload.state['seats'][2]['is_bot']).to be true
    end
  end
end
