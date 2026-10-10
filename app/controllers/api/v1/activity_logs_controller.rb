# frozen_string_literal: true

module Api
  module V1
    class ActivityLogsController < BaseController
      before_action :set_activity_log, only: [ :dev_logs, :cancel, :retry_job ]
      requires_paid_access only: :retry_job

      def index
        logs = current_user.activity_logs.recent.page(params[:page]).per(params[:per].present? ? params[:per].to_i.clamp(1, MAX_PER_PAGE) : 50)
        counts = DevLog.where(parent_type: "ActivityLog", parent_id: logs.map(&:id)).group(:parent_id).count
        render json: {
          activity_logs: logs.map { |log| Serializers.activity_log(log, dev_log_count: counts[log.id] || 0) },
          meta: pagination_meta(logs),
          active: current_user.activity_logs.active.map { |log| Serializers.activity_log(log) },
          stale_count: current_user.activity_logs.stale.count
        }
      end

      # Polled: sweeping here is what clears stranded jobs (see the web's
      # ActivityLogsController#active).
      def active
        current_user.activity_logs.mark_stale_as_failed!
        jobs = current_user.activity_logs.active.to_a
        render json: { active: jobs.any?, jobs: jobs.map { |log| Serializers.activity_log(log) } }
      end

      def dev_logs
        logs = @activity_log.dev_logs.recent.page(params[:page]).per(params[:per].present? ? params[:per].to_i.clamp(1, MAX_PER_PAGE) : 20)
        render json: { dev_logs: logs.map { |log| Serializers.dev_log(log) }, meta: pagination_meta(logs) }
      end

      def cancel
        respond_with ActivityLogs::Actions.cancel(@activity_log)
      end

      def retry_job
        respond_with ActivityLogs::Actions.retry(current_user, @activity_log)
      end

      def cleanup_stale
        result = ActivityLogs::Actions.cleanup_stale(current_user)
        render json: { notice: result.message, count: result.count }
      end

      private

      def set_activity_log
        @activity_log = current_user.activity_logs.find(params[:id])
      end

      def respond_with(result)
        return render_alert(result.message) unless result.ok?

        render json: { notice: result.message }
      end
    end
  end
end
