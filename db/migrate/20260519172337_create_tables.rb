class CreateTables < ActiveRecord::Migration[8.1]
  def change
    create_table :tables do |t|
      t.string  :slug,      null: false
      t.string  :name,      null: false
      t.string  :game_type, null: false, default: 'nl_holdem'
      t.integer :max_seats, null: false, default: 6
      t.json    :state,     null: false, default: {}
      t.timestamps
    end
    add_index :tables, :slug, unique: true
  end
end
