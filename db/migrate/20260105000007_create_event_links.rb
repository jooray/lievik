# frozen_string_literal: true

class CreateEventLinks < ActiveRecord::Migration[8.0]
  def change
    create_table :event_links do |t|
      t.references :event, null: false, foreign_key: true
      t.references :linked_content, null: false, foreign_key: true
      t.integer :link_type, null: false, default: 0
      t.timestamps
    end

    add_index :event_links, [:event_id, :linked_content_id], unique: true
  end
end
