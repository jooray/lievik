# frozen_string_literal: true

class CreateLinkedContents < ActiveRecord::Migration[8.0]
  def change
    create_table :linked_contents do |t|
      t.string :url, null: false, index: { unique: true }
      t.string :title
      t.text :content
      t.json :metadata, default: {}
      t.datetime :fetched_at
      t.timestamps
    end
  end
end
