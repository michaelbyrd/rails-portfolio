class CreateSolidCacheTables < ActiveRecord::Migration[8.1]
  def change
    create_table :solid_cache_entries do |t|
      t.binary  :key,       null: false
      t.binary  :value,     null: false
      t.bigint  :key_hash,  null: false
      t.integer :byte_size, null: false
      t.datetime :created_at, null: false
    end

    add_index :solid_cache_entries, :key_hash, unique: true
    add_index :solid_cache_entries, [:key_hash, :byte_size]
    add_index :solid_cache_entries, :byte_size
  end
end