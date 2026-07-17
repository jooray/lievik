class ChangeChannelContentsContentNullable < ActiveRecord::Migration[8.1]
  def change
    change_column_null :channel_contents, :content, true
  end
end
