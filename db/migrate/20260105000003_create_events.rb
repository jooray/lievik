# frozen_string_literal: true

class CreateEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :events do |t|
      t.references :source, null: false, foreign_key: true
      t.string :external_id, null: false
      t.text :content, null: false
      t.datetime :published_at, null: false
      t.integer :event_type, null: false, default: 0
      t.json :raw_data, default: {}
      t.json :metadata, default: {}
      t.timestamps
    end

    add_index :events, [:source_id, :external_id], unique: true
    add_index :events, :published_at
  end
end
