# frozen_string_literal: true

module Rag
  class VectorStore
    class RubyBackend < VectorStore
      # Cosine similarity is computed in Ruby, so every candidate's ~3KB vector is
      # unpacked into a Ruby float array. Scanning an unbounded table would mean
      # hundreds of MB of allocations per chat question, so we only consider the
      # most recent MAX_CANDIDATES embedded events (recent content is what the RAG
      # chat is about) and stream them in BATCH_SIZE chunks so peak memory stays
      # flat regardless of account size. Override via rag.retrieval.max_candidates.
      MAX_CANDIDATES = 20_000
      BATCH_SIZE = 500

      def search(query_embedding, user:, top_k:, min_similarity:)
        results = []

        # Ids first (cheap), then pull the blobs one batch at a time so at most
        # BATCH_SIZE vectors are resident at once.
        candidate_ids(user).each_slice(BATCH_SIZE) do |ids|
          Event.where(id: ids).pluck(:id, :embedding).each do |id, blob|
            embedding = Rag::EmbeddingService.unpack_embedding(blob)
            next unless embedding

            score = cosine_similarity(query_embedding, embedding)
            next if score < min_similarity

            results << { id: id, score: score }
          end

          # Keep only what we could ever return, so `results` can't grow unbounded.
          results = results.sort_by { |r| -r[:score] }.first(top_k) if results.size > top_k * 4
        end

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
          begin
            embedding = embedding_service.embed(event.content_for_embedding)
            store(event, embedding) if embedding
          rescue StandardError => e
            # One bad response must not abort a full reindex.
            Rails.logger.warn "Failed to reindex event #{event.id}: #{e.class} - #{e.message}"
          end
        end

        user.update!(last_reindexed_at: Time.current)
      end

      private

      def candidate_ids(user)
        Event.joins(source: :user)
             .where(sources: { user_id: user.id })
             .where.not(embedding: nil)
             .order(published_at: :desc)
             .limit(max_candidates)
             .pluck(:id)
      end

      def max_candidates
        configured = Rails.application.config_for(:lievik).dig(:rag, :retrieval, :max_candidates)
        configured.to_i.positive? ? configured.to_i : MAX_CANDIDATES
      end

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
