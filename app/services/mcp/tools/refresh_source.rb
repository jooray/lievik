# frozen_string_literal: true

module Mcp
  module Tools
    class RefreshSource < Base
      def self.description
        "Enqueue a background job to refresh (re-ingest) a single source. Use sparingly — fetches from Nostr relays or RSS."
      end

      def self.input_schema
        {
          type: "object",
          additionalProperties: false,
          required: ["source_id"],
          properties: {
            source_id: { type: "integer" }
          }
        }
      end

      def call
        source = find_user_source!(args[:source_id])
        SourceIngestionJob.perform_later(source.id)

        { ok: true, source: serialize_source(source), enqueued: true }
      end
    end
  end
end
