# frozen_string_literal: true

class ChannelEvent < ApplicationRecord
  # MariaDB has no native JSON type: `t.json` is a longtext plus a
  # CHECK (json_valid(...)) constraint, and the adapter reports it back as
  # `longtext`, so ActiveRecord types the attribute as Text and serializes a
  # Hash with `to_s` — `{"engine" => "chat"}`, which is not JSON and trips the
  # constraint. SQLite (dev) types it correctly and has no constraint, so this
  # only ever fails in production. Every json column in this app needs this
  # line. No default: NULL means "never rated", which is not the same as {}.
  attribute :rating_details, :json

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

  # Bulk flips for a relation (`channel.channel_events.where(...).mark_all_used!`).
  # `update_all` skips callbacks and timestamps, so updated_at is set explicitly:
  # the app API's incremental sync finds changed rows by updated_at, and a used
  # flag that changed without it would never reach the phone. Every bulk
  # used/unused change must go through these two.
  def self.mark_all_used!(at: Time.current)
    update_all(used: true, used_at: at, updated_at: at)
  end

  def self.mark_all_unused!(at: Time.current)
    update_all(used: false, used_at: nil, updated_at: at)
  end

  def mark_used!
    update!(used: true, used_at: Time.current)
  end

  def mark_unused!
    update!(used: false, used_at: nil)
  end
end
