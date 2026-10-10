# frozen_string_literal: true

module Channels
  # Events waiting in each channel's queue, keyed by channel id. Shared by the
  # web channel list and the app API.
  #
  # "Pending" must mean the same thing here as on the channel page: unused AND
  # above that channel's own relevance threshold. Thresholds live in a JSON
  # settings column, so instead of a (DB-specific) json_extract comparison we
  # fold the already-loaded thresholds into a single OR'd predicate — still one
  # query, no N+1, and identical on SQLite and MariaDB.
  module PendingCounts
    def self.for(channels)
      thresholds = channels.map { |c| [ c.id, c.relevance_threshold ] }
      return {} if thresholds.empty?

      predicate = thresholds.map do |id, threshold|
        ChannelEvent.sanitize_sql_array(
          [ "(channel_events.channel_id = ? AND channel_events.relevance_score >= ?)", id, threshold ]
        )
      end.join(" OR ")

      ChannelEvent.unused.where(predicate).group(:channel_id).count
    end
  end
end
