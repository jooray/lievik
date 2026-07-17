# frozen_string_literal: true

module Mcp
  module Tools
    class ListEvents < Base
      DEFAULT_SINCE_DAYS = 7
      DEFAULT_LIMIT = 50

      def self.description
        <<~DESC.strip
          List the user's recent events with their per-channel ratings attached. This is the primary
          "what should I post and where?" feed: each event carries the score and reason from every
          channel that has rated it. Filter by recency, by minimum score in any channel, by source type,
          and by whether the event still has at least one channel where it has not been marked used.
        DESC
      end

      def self.input_schema
        {
          type: "object",
          additionalProperties: false,
          properties: {
            since: {
              type: "string",
              description: "ISO8601 timestamp; only events published at or after this time. Default: 7 days ago."
            },
            only_unused: {
              type: "boolean",
              description: "If true (default), include only events with at least one channel where used=false."
            },
            min_score: {
              type: "integer",
              minimum: 0,
              maximum: 100,
              description: "Include only events that have at least one channel rating >= this score. Default: 0."
            },
            source_type: {
              type: "string",
              enum: %w[nostr rss manual],
              description: "Filter to events from this source type."
            },
            event_type: {
              type: "string",
              enum: %w[original reply repost long_form],
              description: "Filter to a specific event type. Default: no filter."
            },
            limit: {
              type: "integer",
              minimum: 1,
              maximum: MAX_LIMIT,
              description: "Max events to return. Default 50, max 200."
            },
            offset: {
              type: "integer",
              minimum: 0,
              description: "Offset for pagination."
            }
          }
        }
      end

      def call
        since = fetch_time(:since, default: DEFAULT_SINCE_DAYS.days.ago)
        only_unused = fetch_bool(:only_unused, default: true)
        min_score = fetch_int(:min_score, default: 0, min: 0, max: 100)
        limit = fetch_int(:limit, default: DEFAULT_LIMIT, min: 1, max: MAX_LIMIT)
        offset = fetch_int(:offset, default: 0, min: 0, max: 1_000_000)
        source_type = args[:source_type].presence
        event_type = args[:event_type].presence

        scope = user.events
          .includes(:source, channel_events: :channel)
          .where("published_at >= ?", since)
          .order(published_at: :desc)

        scope = scope.joins(:source).where(sources: { source_type: Source.source_types[source_type] }) if source_type
        scope = scope.where(event_type: Event.event_types[event_type]) if event_type

        # Filter to events with at least one channel rating in the user's channels meeting the criteria
        rating_filter = ChannelEvent.joins(:channel).where(channels: { user_id: user.id })
        rating_filter = rating_filter.where("relevance_score >= ?", min_score) if min_score > 0
        rating_filter = rating_filter.where(used: false) if only_unused

        if min_score > 0 || only_unused
          scope = scope.where(id: rating_filter.select(:event_id))
        end

        events = scope.offset(offset).limit(limit).to_a

        result_events = events.map do |event|
          ratings = event.channel_events.select { |ce| ce.channel.user_id == user.id }
          {
            **serialize_event(event,
              channel_ratings: ratings.map { |ce| serialize_channel_event(ce) }
            )
          }
        end

        {
          events: result_events,
          total_returned: result_events.size,
          offset: offset,
          limit: limit,
          since: since.iso8601
        }
      end
    end
  end
end
