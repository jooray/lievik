# frozen_string_literal: true

module Rag
  class VectorStore
    def self.backend
      config = Rails.application.config_for(:lievik).dig(:rag, :vector_backend) || "auto"

      # Only the Ruby backend exists: this app runs on SQLite (dev) and MariaDB
      # (production), so there is no pgvector path to fall back to.
      case config.to_s
      when "ruby", "auto"
        Rag::VectorStore::RubyBackend.new
      else
        raise ArgumentError, "Unknown rag.vector_backend #{config.inspect} (supported: 'ruby', 'auto')"
      end
    end

    # Abstract methods to be implemented by backends
    def search(query_embedding, user:, top_k:, min_similarity:)
      raise NotImplementedError
    end

    def store(event, embedding)
      raise NotImplementedError
    end

    def delete(event_id)
      raise NotImplementedError
    end

    def reindex_user(user)
      raise NotImplementedError
    end
  end
end
