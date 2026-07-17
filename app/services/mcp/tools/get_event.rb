# frozen_string_literal: true

module Mcp
  module Tools
    class GetEvent < Base
      def self.description
        "Fetch a single event with full content, all per-channel ratings, and the linked URLs (with title and summary if fetched)."
      end

      def self.input_schema
        {
          type: "object",
          additionalProperties: false,
          required: ["event_id"],
          properties: {
            event_id: { type: "integer" }
          }
        }
      end

      def call
        event = find_user_event!(args[:event_id])

        ratings = event.channel_events
          .includes(:channel)
          .select { |ce| ce.channel.user_id == user.id }
          .map { |ce| serialize_channel_event(ce) }

        linked = event.linked_contents.map do |lc|
          {
            url: lc.url,
            title: lc.title,
            fetched: lc.fetched_at.present?,
            summary: lc.metadata&.dig("summary"),
            content_excerpt: lc.content.to_s.truncate(800)
          }
        end

        {
          event: serialize_event(event, channel_ratings: ratings, include_links: false),
          linked_contents: linked
        }
      end
    end
  end
end
