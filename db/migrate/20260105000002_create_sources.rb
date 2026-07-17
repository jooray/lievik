# frozen_string_literal: true

class CreateSources < ActiveRecord::Migration[8.0]
  def change
    create_table :sources do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :source_type, null: false, default: 0
      t.string :identifier, null: false
      t.string :name
      t.text :description
      t.integer :distance, null: false, default: 5
      t.json :settings, default: {}
      t.timestamps
    end

    add_index :sources, [:user_id, :source_type, :identifier], unique: true
  end
end
