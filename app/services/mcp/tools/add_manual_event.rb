# frozen_string_literal: true

module Mcp
  module Tools
    class AddManualEvent < Base
      def self.description
        "Add a manual event to the user's manual source. Triggers link extraction and rates the new event against all channels."
      end

      def self.input_schema
        {
          type: "object",
          additionalProperties: false,
          required: ["content"],
          properties: {
            content: { type: "string", description: "Event content (may include URLs which will be extracted)." },
            published_at: { type: "string", description: "ISO8601 published_at; default: now." }
          }
        }
      end

      def call
        content = args[:content].to_s
        raise InvalidParams, "content required" if content.strip.empty?

        published_at = fetch_time(:published_at, default: Time.current)

        result = ManualEvents::Creator.new(user, content: content, published_at: published_at).call
        raise AppError, result.errors.join(", ") unless result.success?

        { ok: true, event: serialize_event(result.event, channel_ratings: []) }
      end
    end
  end
end
