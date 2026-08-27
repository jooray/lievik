# frozen_string_literal: true

class ChannelEvent < ApplicationRecord
  belongs_to :channel
  belongs_to :event

  validates :event_id, uniqueness: { scope: :channel_id }

  scope :unused, -> { where(used: false) }
  scope :used, -> { where(used: true) }
  scope :above_threshold, ->(threshold) { where("relevance_score >= ?", threshold) }
  scope :by_relevance, -> { order(relevance_score: :desc) }
  # Recency sorts live on events.published_at, so they need the join. Ties are
  # broken on channel_events.id so a paginated list can't repeat or drop a row
  # when several events share a timestamp.
  scope :by_newest, -> { joins(:event).order("events.published_at DESC, channel_events.id DESC") }
  scope :by_oldest, -> { joins(:event).order("events.published_at ASC, channel_events.id ASC") }

  def mark_used!
    update!(used: true, used_at: Time.current)
  end

  def mark_unused!
    update!(used: false, used_at: nil)
  end
end
