class AddSystemPromptToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :system_prompt, :text
  end
end
