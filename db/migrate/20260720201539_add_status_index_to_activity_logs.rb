# frozen_string_literal: true

# The `active` and `stale` scopes are now hit on every dashboard render and on
# every poll of /activity_logs/active. Without this they fall back to the
# user_id index and scan that user's entire log history (tens of thousands of
# rows on an active install, since logs are kept for 30 days).
class AddStatusIndexToActivityLogs < ActiveRecord::Migration[8.1]
  def change
    add_index :activity_logs, [:user_id, :status, :updated_at],
      name: "index_activity_logs_on_user_status_updated"
  end
end
