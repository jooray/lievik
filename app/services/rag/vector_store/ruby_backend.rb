# frozen_string_literal: true

module Rag
  class VectorStore
    class RubyBackend < VectorStore
      def search(query_embedding, user:, top_k:, min_similarity:)
        # Load only this user's events with embeddings
        user_events = Event.joins(source: :user)
                           .where(sources: { user_id: user.id })
                           .where.not(embedding: nil)
                           .select(:id, :embedding)

        # Compute similarities in Ruby
        results = user_events.filter_map do |event|
          embedding = Rag::EmbeddingService.unpack_embedding(event.embedding)
          next unless embedding

          score = cosine_similarity(query_embedding, embedding)
          next if score < min_similarity

          { id: event.id, score: score }
        end

        # Sort by score descending and take top_k
        results.sort_by { |r| -r[:score] }.first(top_k)
      end

      def store(event, embedding)
        binary = embedding.is_a?(Array) ? embedding.pack("f*") : embedding
        event.update!(embedding: binary, embedded_at: Time.current)
      end

      def delete(event_id)
        Event.where(id: event_id).update_all(embedding: nil, embedded_at: nil)
      end

      def reindex_user(user)
        embedding_service = Rag::EmbeddingService.new

        # Get all events for this user
        events = Event.joins(source: :user)
                      .where(sources: { user_id: user.id })
                      .where.not(content: [nil, ""])

        events.find_each do |event|
          embedding = embedding_service.embed(event.content_for_embedding)
          store(event, embedding) if embedding
        end

        user.update!(last_reindexed_at: Time.current)
      end

      private

      def cosine_similarity(a, b)
        return 0.0 if a.nil? || b.nil? || a.empty? || b.empty?
        return 0.0 if a.length != b.length

        dot = 0.0
        mag_a = 0.0
        mag_b = 0.0

        a.each_with_index do |val_a, i|
          val_b = b[i]
          dot += val_a * val_b
          mag_a += val_a * val_a
          mag_b += val_b * val_b
        end

        magnitude = Math.sqrt(mag_a) * Math.sqrt(mag_b)
        return 0.0 if magnitude.zero?

        dot / magnitude
      end
    end
  end
end
