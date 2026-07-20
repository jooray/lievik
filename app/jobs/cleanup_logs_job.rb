# frozen_string_literal: true

# Trims the two tables that otherwise grow forever:
#   * dev_logs — two rows per rated event, each holding a full prompt/response
#     (up to ~4KB), so they dominate the DB on any active install.
#   * activity_logs — one row per ingestion/rating run, never deleted.
#
# Deletion runs in batches so a large table is never locked in one statement.
# Retention windows are configurable via ENV (DEV_LOG_RETENTION_DAYS /
# ACTIVITY_LOG_RETENTION_DAYS).
class CleanupLogsJob < ApplicationJob
  queue_as :default

  DEV_LOG_RETENTION_DAYS = Integer(ENV.fetch("DEV_LOG_RETENTION_DAYS", 7))
  ACTIVITY_LOG_RETENTION_DAYS = Integer(ENV.fetch("ACTIVITY_LOG_RETENTION_DAYS", 30))
  BATCH_SIZE = 1_000

  def perform(dev_log_days: DEV_LOG_RETENTION_DAYS, activity_log_days: ACTIVITY_LOG_RETENTION_DAYS)
    dev_logs_deleted = delete_in_batches(DevLog.where(created_at: ...dev_log_days.days.ago))

    # Dev logs attached to an expiring activity log go first (the association is
    # dependent: :destroy, but delete_all bypasses callbacks).
    stale_activities = ActivityLog.where(created_at: ...activity_log_days.days.ago)
    dev_logs_deleted += delete_in_batches(
      DevLog.where(parent_type: "ActivityLog", parent_id: stale_activities.select(:id))
    )
    activity_logs_deleted = delete_in_batches(stale_activities)

    Rails.logger.info(
      "CleanupLogsJob deleted #{dev_logs_deleted} dev_logs (>#{dev_log_days}d) and " \
      "#{activity_logs_deleted} activity_logs (>#{activity_log_days}d)"
    )
  end

  private

  def delete_in_batches(scope)
    deleted = 0
    scope.in_batches(of: BATCH_SIZE) { |batch| deleted += batch.delete_all }
    deleted
  end
end
