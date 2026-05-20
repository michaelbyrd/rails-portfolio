require 'rails_helper'

RSpec.describe 'Card room index', type: :system do
  it 'shows the card room page' do
    visit card_room_path
    expect(page).to have_text('Card Room')
    expect(page).to have_text("No Limit Hold'em")
  end

  it 'lists seeded tables' do
    create(:table, name: 'Test Table')
    visit card_room_path
    expect(page).to have_text('Test Table')
  end

  it 'navigates to a table page' do
    table = create(:table, name: 'High Stakes')
    visit card_room_path
    click_on 'High Stakes'
    expect(page).to have_current_path(card_room_table_path(table.slug))
  end
end
