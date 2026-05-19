# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

[
  { name: "Table 1", game_type: "nl_holdem", max_seats: 6 },
  { name: "Table 2", game_type: "nl_holdem", max_seats: 6 },
  { name: "Table 3", game_type: "nl_holdem", max_seats: 6 },
].each do |attrs|
  Table.find_or_create_by!(name: attrs[:name]) do |t|
    t.game_type = attrs[:game_type]
    t.max_seats = attrs[:max_seats]
  end
end
