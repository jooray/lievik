# frozen_string_literal: true

module Mcp
  module Tools
    class MarkEventUnused < Base
      def self.description
        "Mark an event as no longer used in a specific channel. Clears used and used_at."
      end

      def self.input_schema
        {
          type: "object",
          additionalProperties: false,
          required: %w[channel_id event_id],
          properties: {
            channel_id: { type: "integer" },
            event_id: { type: "integer" }
          }
        }
      end

      def call
        channel = find_user_channel!(args[:channel_id])
        ce = channel.channel_events.find_by!(event_id: args[:event_id])
        ce.mark_unused!

        { ok: true, channel_event: serialize_channel_event(ce.tap(&:reload)) }
      end
    end
  end
end
