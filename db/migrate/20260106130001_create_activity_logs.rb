# frozen_string_literal: true

class CreateActivityLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :activity_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.string :activity_type, null: false
      t.string :status, default: "pending"
      t.text :message
      t.json :metadata, default: {}
      t.datetime :completed_at

      t.timestamps
    end

    add_index :activity_logs, [:user_id, :created_at]
    add_index :activity_logs, :activity_type
  end
end
