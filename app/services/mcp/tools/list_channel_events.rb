# frozen_string_literal: true

module Mcp
  module Tools
    class ListChannelEvents < Base
      DEFAULT_LIMIT = 50

      def self.description
        "List events rated for a specific channel, sorted by relevance score descending. Filter by min score, used/unused, and recency."
      end

      def self.input_schema
        {
          type: "object",
          additionalProperties: false,
          required: ["channel_id"],
          properties: {
            channel_id: { type: "integer", description: "ID of the channel" },
            min_score: { type: "integer", minimum: 0, maximum: 100, description: "Minimum relevance score. Default: channel's own threshold." },
            only_unused: { type: "boolean", description: "If true (default), only events not yet marked used." },
            limit: { type: "integer", minimum: 1, maximum: MAX_LIMIT, description: "Default 50, max 200." },
            offset: { type: "integer", minimum: 0 }
          }
        }
      end

      def call
        channel = find_user_channel!(args[:channel_id])
        only_unused = fetch_bool(:only_unused, default: true)
        min_score = fetch_int(:min_score, default: channel.relevance_threshold, min: 0, max: 100)
        limit = fetch_int(:limit, default: DEFAULT_LIMIT, min: 1, max: MAX_LIMIT)
        offset = fetch_int(:offset, default: 0, min: 0, max: 1_000_000)

        scope = channel.channel_events
          .includes(event: :source, channel: nil)
          .above_threshold(min_score)
          .by_relevance
        scope = scope.unused if only_unused

        ces = scope.offset(offset).limit(limit).to_a

        events = ces.map do |ce|
          serialize_event(ce.event, channel_ratings: [serialize_channel_event_in_context(ce, channel)])
        end

        {
          channel: serialize_channel(channel),
          events: events,
          total_returned: events.size,
          offset: offset,
          limit: limit
        }
      end

      private

      def serialize_channel_event_in_context(ce, channel)
        {
          channel_id: channel.id,
          channel_name: channel.name,
          score: ce.relevance_score,
          reason: ce.relevance_reason,
          used: ce.used,
          used_at: ce.used_at&.iso8601
        }
      end
    end
  end
end
