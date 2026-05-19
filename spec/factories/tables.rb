FactoryBot.define do
  factory :table do
    sequence(:slug) { |n| "tbl#{n.to_s.rjust(5, '0')}" }
    sequence(:name) { |n| "Table #{n}" }
    game_type { 'nl_holdem' }
    max_seats { 6 }
  end
end
