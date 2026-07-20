# frozen_string_literal: true

class ChannelContent < ApplicationRecord
  attribute :version_history, :json, default: -> { [] }

  belongs_to :channel
  belongs_to :user
  has_many :channel_content_events, dependent: :destroy
  has_many :events, through: :channel_content_events

  enum :status, { draft: 0, published: 1 }

  # Content is optional on create (draft starts empty), required only for publish
  validates :content, presence: true, if: :published?

  scope :recent, -> { order(created_at: :desc) }
  scope :published_content, -> { where(status: :published).order(published_at: :desc) }
  scope :drafts, -> { where(status: :draft).order(updated_at: :desc) }

  def publish!
    update!(status: :published, published_at: Time.current)
    mark_events_as_used!
  end

  def add_version(old_content)
    return if old_content.blank?

    # Read-modify-write on a JSON column: without the row lock two concurrent
    # saves/reverts both start from the same history and one version is lost.
    with_lock do
      new_history = version_history || []
      new_history << {
        content: old_content,
        saved_at: Time.current.iso8601,
        version: new_history.size + 1
      }
      # Keep only last 10 versions
      new_history = new_history.last(10)
      update_column(:version_history, new_history)
    end
  end

  def previous_version
    return nil if version_history.blank?

    version_history.last
  end

  def revert_to_previous!
    # The whole pop-then-push must be atomic, otherwise a concurrent save can
    # interleave and drop a version.
    with_lock do
      previous = previous_version
      next false if previous.nil?

      old_content = content
      new_content = previous["content"]

      # Remove the last version from history
      new_history = version_history[0..-2]

      update!(content: new_content, version_history: new_history)

      # Add current content as a new version so user can undo the revert
      add_version(old_content)

      true
    end
  end

  private

  def mark_events_as_used!
    event_ids = events.pluck(:id)
    return if event_ids.empty?

    channel.channel_events.where(event_id: event_ids).update_all(
      used: true,
      used_at: Time.current
    )
  end
end
