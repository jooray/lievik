# frozen_string_literal: true

class ActivityLog < ApplicationRecord
  attribute :metadata, :json, default: -> { {} }

  has_many :dev_logs, as: :parent, dependent: :destroy
  belongs_to :user

  enum :status, { pending: "pending", running: "running", completed: "completed", failed: "failed" }

  ACTIVITY_TYPES = %w[ingestion rating].freeze

  validates :activity_type, presence: true, inclusion: { in: ACTIVITY_TYPES }

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(status: [:pending, :running]) }
  scope :stale, -> { active.where("updated_at < ?", 15.minutes.ago) }

  after_create_commit :broadcast_job_created
  after_update_commit :broadcast_job_updated

  def self.mark_stale_as_failed!
    stale.find_each do |activity|
      activity.fail!(message: "Job stale — no progress for #{activity.minutes_since_last_update} minutes")
    end
  end

  def self.start_activity(user:, activity_type:, message: nil, metadata: {})
    create!(
      user: user,
      activity_type: activity_type,
      status: :running,
      message: message,
      metadata: metadata
    )
  end

  def complete!(message: nil)
    update!(
      status: :completed,
      message: message || self.message,
      completed_at: Time.current
    )
  end

  def fail!(message:)
    update!(
      status: :failed,
      message: message,
      completed_at: Time.current
    )
  end

  def update_progress(current:, total:, message: nil)
    self.metadata["progress"] = { current: current, total: total }
    self.message = message if message
    save!
  end

  def progress_percentage
    return nil unless metadata["progress"]

    total = metadata["progress"]["total"].to_i
    return 0 if total.zero?

    current = metadata["progress"]["current"].to_i
    (current.to_f / total * 100).round
  end

  def duration
    return nil unless completed_at

    completed_at - created_at
  end

  def hours_running
    ((Time.current - created_at) / 1.hour).round(1)
  end

  def minutes_since_last_update
    ((Time.current - updated_at) / 1.minute).round
  end

  def stale?
    active? && updated_at < 15.minutes.ago
  end

  def active?
    pending? || running?
  end

  private

  def broadcast_job_created
    return unless active?

    broadcast_append_to "activity_logs_#{user_id}",
      target: "job_progress_container",
      partial: "activity_logs/job_progress_card",
      locals: { job: self }
  end

  def broadcast_job_updated
    if active?
      broadcast_replace_to "activity_logs_#{user_id}",
        partial: "activity_logs/job_progress_card",
        locals: { job: self }
    else
      broadcast_remove_to "activity_logs_#{user_id}"
    end
  end
end
