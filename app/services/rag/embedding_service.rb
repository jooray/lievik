# frozen_string_literal: true

module Rag
  class EmbeddingService
    class EmbeddingError < StandardError; end

    def initialize
      @config = Rails.application.config_for(:lievik).dig(:rag, :embedding) || {}
      @ollama_url = @config[:ollama_url] || "http://localhost:11434/api/embeddings"
      @model = @config[:model] || "nomic-embed-text"
      @max_chars = @config[:max_chars] || 8000
    end

    def embed(text)
      return nil if text.blank?

      # Truncate to stay within model's context limit (configurable in lievik.yml)
      # Use omission: '' to avoid adding "..." which could push over the limit
      truncated_text = text.to_s.strip.truncate(@max_chars, omission: "")

      response = HTTPX.post(@ollama_url, json: {
        model: @model,
        prompt: truncated_text
      })

      unless response.status == 200
        raise EmbeddingError, "Ollama embedding failed: #{response.status} - #{response.body}"
      end

      result = JSON.parse(response.body)
      result["embedding"]
    rescue HTTPX::Error => e
      raise EmbeddingError, "Failed to connect to Ollama: #{e.message}"
    end

    def embed_to_binary(text)
      embedding = embed(text)
      return nil unless embedding

      # Pack as array of floats (4 bytes each)
      embedding.pack("f*")
    end

    def self.unpack_embedding(binary)
      return nil if binary.nil?

      binary.unpack("f*")
    end
  end
end
