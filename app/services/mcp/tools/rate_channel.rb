# frozen_string_literal: true

module Mcp
  module Tools
    class RateChannel < Base
      def self.description
        "Enqueue a background job to (re-)rate events for a channel. Picks up unrated and recent events."
      end

      def self.input_schema
        {
          type: "object",
          additionalProperties: false,
          required: ["channel_id"],
          properties: {
            channel_id: { type: "integer" }
          }
        }
      end

      def call
        channel = find_user_channel!(args[:channel_id])
        RateEventsJob.perform_later(channel.id)

        { ok: true, channel: serialize_channel(channel), enqueued: true }
      end
    end
  end
end
