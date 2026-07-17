# frozen_string_literal: true

class CreateChannelContentEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :channel_content_events do |t|
      t.references :channel_content, null: false, foreign_key: true
      t.references :event, null: false, foreign_key: true

      t.timestamps
    end

    add_index :channel_content_events, [:channel_content_id, :event_id], unique: true
  end
end
