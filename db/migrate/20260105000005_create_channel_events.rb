# frozen_string_literal: true

class CreateChannelEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :channel_events do |t|
      t.references :channel, null: false, foreign_key: true
      t.references :event, null: false, foreign_key: true
      t.integer :relevance_score
      t.boolean :used, null: false, default: false
      t.datetime :used_at
      t.timestamps
    end

    add_index :channel_events, [:channel_id, :event_id], unique: true
    add_index :channel_events, [:channel_id, :relevance_score]
    add_index :channel_events, [:channel_id, :used]
  end
end
