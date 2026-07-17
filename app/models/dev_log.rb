# frozen_string_literal: true

class DevLog < ApplicationRecord
  attribute :details, :json, default: -> { {} }

  belongs_to :user
  belongs_to :parent, polymorphic: true, optional: true

  enum :log_type, {
    ai_request: 'ai_request',
    ai_response: 'ai_response',
    ingestion_event: 'ingestion_event',
    ingestion_error: 'ingestion_error',
    rating_error: 'rating_error',
    content_error: 'content_error'
  }

  scope :recent, -> { order(created_at: :desc) }
  scope :for_activity, ->(activity_log) { where(parent_type: 'ActivityLog', parent_id: activity_log.id) }
end
