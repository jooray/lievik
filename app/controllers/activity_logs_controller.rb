# frozen_string_literal: true

class ActivityLogsController < ApplicationController
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
    activity_log = current_user.activity_logs.find(params[:id])
    if activity_log.active?
      activity_log.fail!(message: "Cancelled by user")
      redirect_to activity_logs_path, notice: "Job cancelled."
    else
      redirect_to activity_logs_path, alert: "Job is already #{activity_log.status}."
    end
  end

  def retry_job
    activity_log = current_user.activity_logs.find(params[:id])
    channel_id = activity_log.metadata["channel_id"]

    if channel_id.blank?
      redirect_to activity_logs_path, alert: "Cannot retry — no channel associated with this job."
      return
    end

    channel = current_user.channels.find_by(id: channel_id)
    if channel.nil?
      redirect_to activity_logs_path, alert: "Cannot retry — channel no longer exists."
      return
    end

    RateEventsJob.perform_later(channel.id)
    redirect_to activity_logs_path, notice: "Re-queued rating job for #{channel.name}."
  end

  def cleanup_stale
    stale_count = current_user.activity_logs.stale.count
    current_user.activity_logs.stale.find_each do |activity|
      activity.fail!(message: "Job stale — no progress for #{activity.minutes_since_last_update} minutes")
    end

    redirect_to activity_logs_path, notice: "Cleaned up #{stale_count} stale job(s)."
  end
end

