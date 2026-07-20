# frozen_string_literal: true

class AddPerformanceIndexes < ActiveRecord::Migration[8.1]
  def change
    # Channel feed: channel_id = ? AND used = ? AND relevance_score >= ? ORDER BY relevance_score DESC
    add_index :channel_events, [:channel_id, :used, :relevance_score],
              name: "index_channel_events_on_channel_used_relevance",
              if_not_exists: true

    # Per-source event lists ordered by recency
    add_index :events, [:source_id, :published_at], if_not_exists: true

    # nostr: reference resolution does Event.find_by(external_id:), which cannot
    # use the leftmost prefix of (source_id, external_id).
    add_index :events, :external_id, if_not_exists: true

    # nostr: profile resolution does Source.find_by(identifier:, source_type:),
    # which cannot use the leftmost prefix of (user_id, source_type, identifier).
    add_index :sources, :identifier, if_not_exists: true
  end
end
