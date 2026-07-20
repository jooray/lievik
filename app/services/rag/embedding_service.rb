# frozen_string_literal: true

module Rag
  class EmbeddingService
    class EmbeddingError < StandardError; end

    # Explicit timeouts: without them a stalled Ollama pins a queue thread forever.
    CONNECT_TIMEOUT = 5
    READ_TIMEOUT = 60

    def initialize
      @config = Rails.application.config_for(:lievik).dig(:rag, :embedding) || {}
      @ollama_url = @config[:ollama_url] || "http://localhost:11434/api/embeddings"
      @model = @config[:model] || "nomic-embed-text"
      @max_chars = @config[:max_chars] || 8000
      @dimension = (@config[:dimensions] || @config[:dimension])&.to_i
    end

    def embed(text)
      return nil if text.blank?

      # Truncate to stay within model's context limit (configurable in lievik.yml)
      # Use omission: '' to avoid adding "..." which could push over the limit
      truncated_text = text.to_s.strip.truncate(@max_chars, omission: "")

      response = http_client.post(@ollama_url, json: {
        model: @model,
        prompt: truncated_text
      })

      if response.is_a?(HTTPX::ErrorResponse)
        raise EmbeddingError, "Failed to connect to Ollama: #{response.error&.message}"
      end

      unless response.status == 200
        raise EmbeddingError, "Ollama embedding failed: #{response.status} - #{response.body.to_s.truncate(500)}"
      end

      begin
        result = JSON.parse(response.body.to_s)
      rescue JSON::ParserError => e
        raise EmbeddingError, "Malformed Ollama response: #{e.message}"
      end

      validate_embedding!(result.is_a?(Hash) ? result["embedding"] : nil)
    rescue HTTPX::Error, IOError, SystemCallError => e
      raise EmbeddingError, "Failed to connect to Ollama: #{e.class} - #{e.message}"
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

    private

    def http_client
      @http_client ||= HTTPX.with(
        timeout: {
          connect_timeout: CONNECT_TIMEOUT,
          read_timeout: READ_TIMEOUT,
          write_timeout: READ_TIMEOUT,
          request_timeout: READ_TIMEOUT
        }
      )
    end

    # A malformed/short vector poisons the index silently, so reject it here and
    # let the caller decide (the job skips the event and moves on).
    def validate_embedding!(embedding)
      unless embedding.is_a?(Array) && embedding.any?
        raise EmbeddingError, "Ollama returned no embedding array"
      end

      unless embedding.all? { |v| v.is_a?(Numeric) && v.to_f.finite? }
        raise EmbeddingError, "Ollama returned a non-numeric embedding"
      end

      if @dimension&.positive? && embedding.length != @dimension
        raise EmbeddingError, "Unexpected embedding dimension #{embedding.length} (expected #{@dimension})"
      end

      embedding
    end
  end
end
