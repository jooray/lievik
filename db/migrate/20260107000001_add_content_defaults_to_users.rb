# frozen_string_literal: true

class AddContentDefaultsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :default_content_style, :text
    add_column :users, :content_templates, :json, default: []
  end
end
