class CreateSongs < ActiveRecord::Migration[8.1]
  def change
    create_table :songs do |t|
      t.string :slug, null: false
      t.string :name
      t.json :state, null: false, default: {}
      t.timestamps
    end
    add_index :songs, :slug, unique: true
  end
end
