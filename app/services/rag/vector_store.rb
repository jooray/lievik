# frozen_string_literal: true

module Rag
  class VectorStore
    def self.backend
      config = Rails.application.config_for(:lievik).dig(:rag, :vector_backend) || "auto"

      case config.to_s
      when "pgvector"
        Rag::VectorStore::PgvectorBackend.new
      when "ruby"
        Rag::VectorStore::RubyBackend.new
      else # 'auto'
        if ActiveRecord::Base.connection.adapter_name == "PostgreSQL"
          # Check if pgvector extension is available
          begin
            ActiveRecord::Base.connection.execute("SELECT 1 FROM pg_extension WHERE extname = 'vector'")
            Rag::VectorStore::PgvectorBackend.new
          rescue StandardError
            Rag::VectorStore::RubyBackend.new
          end
        else
          Rag::VectorStore::RubyBackend.new
        end
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
