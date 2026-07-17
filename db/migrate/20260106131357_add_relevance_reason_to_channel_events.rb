class AddRelevanceReasonToChannelEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :channel_events, :relevance_reason, :text
  end
end
