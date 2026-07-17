# frozen_string_literal: true

class EmbedEventsJob < ApplicationJob
  queue_as :default

  def perform(event_ids)
    return if event_ids.blank?

    embedding_service = Rag::EmbeddingService.new
    vector_store = Rag::VectorStore.backend

    Event.where(id: event_ids).find_each do |event|
      next if event.content.blank?

      begin
        embedding = embedding_service.embed(event.content_for_embedding)
        vector_store.store(event, embedding) if embedding
      rescue Rag::EmbeddingService::EmbeddingError => e
        Rails.logger.warn "Failed to embed event #{event.id}: #{e.message}"
      end
    end
  end
end
