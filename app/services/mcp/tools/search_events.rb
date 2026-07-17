# frozen_string_literal: true

module Mcp
  module Tools
    class SearchEvents < Base
      DEFAULT_LIMIT = 10
      MAX_SEARCH_LIMIT = 50
      MIN_SIMILARITY = 0.3

      def self.description
        "Semantic search over the user's events using embeddings. Returns events ranked by similarity to the query."
      end

      def self.input_schema
        {
          type: "object",
          additionalProperties: false,
          required: ["query"],
          properties: {
            query: { type: "string", description: "Free-text query." },
            limit: { type: "integer", minimum: 1, maximum: MAX_SEARCH_LIMIT, description: "Default 10, max 50." },
            min_similarity: { type: "number", minimum: 0.0, maximum: 1.0, description: "Cosine similarity floor 0..1. Default 0.3." }
          }
        }
      end

      def call
        query = args[:query].to_s.strip
        raise InvalidParams, "query required" if query.blank?

        limit = fetch_int(:limit, default: DEFAULT_LIMIT, min: 1, max: MAX_SEARCH_LIMIT)
        min_similarity = (args[:min_similarity] || MIN_SIMILARITY).to_f

        embedding_service = Rag::EmbeddingService.new
        query_embedding = embedding_service.embed(query)
        raise AppError, "Failed to embed query" unless query_embedding

        store = Rag::VectorStore.backend
        hits = store.search(query_embedding, user: user, top_k: limit, min_similarity: min_similarity)

        return { events: [], query: query } if hits.empty?

        events_by_id = user.events
          .where(id: hits.map { |h| h[:id] })
          .includes(:source, channel_events: :channel)
          .index_by(&:id)

        results = hits.filter_map do |hit|
          event = events_by_id[hit[:id]]
          next unless event

          ratings = event.channel_events
            .select { |ce| ce.channel.user_id == user.id }
            .map { |ce| serialize_channel_event(ce) }

          serialize_event(event, channel_ratings: ratings).merge(similarity: hit[:score].round(4))
        end

        { events: results, query: query }
      end
    end
  end
end
