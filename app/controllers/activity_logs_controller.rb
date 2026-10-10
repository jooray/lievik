# frozen_string_literal: true

class ActivityLogsController < ApplicationController
  requires_paid_access only: :retry_job

  def index
    @activity_logs = current_user.activity_logs.recent.page(params[:page]).per(50)
    @active_jobs = current_user.activity_logs.active
    @stale_jobs = current_user.activity_logs.stale
    @dev_log_counts = DevLog.where(parent_type: "ActivityLog", parent_id: @activity_logs.map(&:id))
      .group(:parent_id)
      .count
  end

  def active
    # Polled endpoint — sweeping here is what actually clears stranded cards
    # from an open dashboard without a reload. See DashboardController#index.
    current_user.activity_logs.mark_stale_as_failed!
    @active_jobs = current_user.activity_logs.active

    respond_to do |format|
      format.turbo_stream
      format.json do
        render json: {
          active: @active_jobs.any?,
          jobs: @active_jobs.map do |job|
            {
              id: job.id,
              type: job.activity_type,
              message: job.message,
              progress: job.progress_percentage
            }
          end
        }
      end
    end
  end

  def dev_logs
    @activity_log = current_user.activity_logs.find(params[:id])
    @dev_logs = @activity_log.dev_logs.recent.page(params[:page]).per(20)
  end

  def all_dev_logs
    @dev_logs = DevLog.where(user: current_user).order(created_at: :desc).page(params[:page]).per(50)
  end

  def cancel
    result = ActivityLogs::Actions.cancel(current_user.activity_logs.find(params[:id]))
    redirect_to activity_logs_path, (result.ok? ? :notice : :alert) => result.message
  end

  def retry_job
    result = ActivityLogs::Actions.retry(current_user, current_user.activity_logs.find(params[:id]))
    redirect_to activity_logs_path, (result.ok? ? :notice : :alert) => result.message
  end

  def cleanup_stale
    redirect_to activity_logs_path, notice: ActivityLogs::Actions.cleanup_stale(current_user).message
  end
end
