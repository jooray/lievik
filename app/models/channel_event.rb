# frozen_string_literal: true

class ChannelEvent < ApplicationRecord
  belongs_to :channel
  belongs_to :event

  validates :event_id, uniqueness: { scope: :channel_id }

  scope :unused, -> { where(used: false) }
  scope :used, -> { where(used: true) }
  scope :above_threshold, ->(threshold) { where("relevance_score >= ?", threshold) }
  scope :by_relevance, -> { order(relevance_score: :desc) }

  def mark_used!
    update!(used: true, used_at: Time.current)
  end

  def mark_unused!
    update!(used: false, used_at: nil)
  end
end
