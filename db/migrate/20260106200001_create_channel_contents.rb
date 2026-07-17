# frozen_string_literal: true

class CreateChannelContents < ActiveRecord::Migration[8.1]
  def change
    create_table :channel_contents do |t|
      t.references :channel, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :title
      t.text :content, null: false
      t.integer :status, default: 0, null: false
      t.datetime :published_at
      t.json :version_history, default: []

      t.timestamps
    end

    add_index :channel_contents, [:channel_id, :status]
    add_index :channel_contents, [:channel_id, :created_at]
  end
end
