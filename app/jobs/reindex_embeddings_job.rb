# frozen_string_literal: true

class ReindexEmbeddingsJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    vector_store = Rag::VectorStore.backend
    embedding_service = Rag::EmbeddingService.new

    events = Event.joins(source: :user)
                  .where(sources: { user_id: user.id })
                  .where.not(content: [nil, ""])

    total = events.count
    embedded = 0
    failed = 0

    events.find_each do |event|
      begin
        embedding = embedding_service.embed(event.content)
        vector_store.store(event, embedding) if embedding
        embedded += 1
      rescue => e
        Rails.logger.warn "Failed to embed event #{event.id}: #{e.message}"
        failed += 1
      end
    end

    user.update!(last_reindexed_at: Time.current)
    Rails.logger.info "Reindex complete for user #{user_id}: #{embedded}/#{total} embedded, #{failed} failed"
  end
end
