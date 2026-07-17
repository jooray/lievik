# frozen_string_literal: true

class AddEmbeddingsToEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :events, :embedding, :binary
    add_column :events, :embedded_at, :datetime
    add_column :linked_contents, :embedding, :binary
    add_column :linked_contents, :embedded_at, :datetime
    add_column :users, :last_reindexed_at, :datetime
  end
end
