# frozen_string_literal: true

module ActivityLogs
  # Cancel / retry / clean up for the activity log. Shared by
  # ActivityLogsController and the app API.
  module Actions
    Result = Struct.new(:ok, :message, :count, keyword_init: true) do
      def ok? = ok
    end

    def self.cancel(activity_log)
      if activity_log.active?
        activity_log.fail!(message: "Cancelled by user")
        Result.new(ok: true, message: I18n.t("activity_logs.cancel.notice"))
      else
        Result.new(ok: false, message: I18n.t("activity_logs.cancel.already_finished",
                                             status: I18n.t("activity_logs.statuses.#{activity_log.status}")))
      end
    end

    # Callers gate this with requires_paid_access.
    def self.retry(user, activity_log)
      channel_id = activity_log.metadata["channel_id"]
      return Result.new(ok: false, message: I18n.t("activity_logs.retry_job.no_channel")) if channel_id.blank?

      channel = user.channels.find_by(id: channel_id)
      return Result.new(ok: false, message: I18n.t("activity_logs.retry_job.channel_missing")) if channel.nil?

      RateEventsJob.perform_later(channel.id)
      Result.new(ok: true, message: I18n.t("activity_logs.retry_job.notice", channel: channel.name))
    end

    def self.cleanup_stale(user)
      stale = user.activity_logs.stale
      count = stale.count
      stale.find_each do |activity|
        activity.fail!(message: "Job stale — no progress for #{activity.minutes_since_last_update} minutes")
      end
      Result.new(ok: true, count: count, message: I18n.t("activity_logs.cleanup_stale.notice", count: count))
    end
  end
end
