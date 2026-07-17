# frozen_string_literal: true

class CreateChannels < ActiveRecord::Migration[8.0]
  def change
    create_table :channels do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :language, null: false, default: 'en'
      t.text :prompt
      t.json :settings, default: {}
      t.timestamps
    end
  end
end
