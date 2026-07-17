# frozen_string_literal: true

class AddContentSettingsToChannels < ActiveRecord::Migration[8.1]
  def change
    add_column :channels, :content_prompt, :text
    add_column :channels, :content_language, :string
    add_column :channels, :content_style, :string
  end
end
