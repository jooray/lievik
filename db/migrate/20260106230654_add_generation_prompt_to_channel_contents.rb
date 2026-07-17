class AddGenerationPromptToChannelContents < ActiveRecord::Migration[8.1]
  def change
    add_column :channel_contents, :generation_prompt, :text
  end
end
