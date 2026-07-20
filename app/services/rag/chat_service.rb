# frozen_string_literal: true

module Rag
  class ChatService
    SYSTEM_PROMPT = <<~PROMPT
      You are a helpful assistant answering questions about the user's content library.

      IMPORTANT RULES:
      1. Answer naturally as if you have direct knowledge of the information below.
      2. You MUST cite sources using [EVENT:id] format inline when referencing specific information.
      3. Only use information from what's provided - if it doesn't contain relevant info, say "I don't have information about that in your library."
      4. Format your response using markdown (headers, lists, bold, etc. as appropriate).
      5. NEVER use meta-phrases like "Based on the provided context", "According to the documents", "From the information given", or "In the context provided" - just answer directly as if you naturally know this information.

      Answer the user's question naturally with [EVENT:123] citations inline...
    PROMPT

    QUERY_REWRITE_PROMPT = <<~PROMPT
      You are a search query optimizer for a content library.

      Given the conversation history (if any) and current question, generate an optimized search query.
      Rules:
      - Make implicit references explicit (resolve "it", "that", pronouns using history)
      - Expand abbreviations (BTC → Bitcoin, ETH → Ethereum)
      - Add relevant synonyms and related terms
      - Remove filler words, keep key concepts
      - Output ONLY the optimized query, nothing else
      - Keep it concise (under 50 words)
    PROMPT

    def initialize(user)
      @user = user
      @config = Rails.application.config_for(:lievik)[:rag] || {}
      @vector_store = Rag::VectorStore.backend
      @embedding_service = Rag::EmbeddingService.new
      @ai_client = Ai::Client.new(use_case: :rag_chat)
      @query_rewrite_client = initialize_query_rewrite_client
    end

    def chat(question, conversation_history: [])
      # 0. Rewrite query for better retrieval
      search_query = rewrite_query(question, conversation_history)

      # 1. Embed the rewritten question
      query_embedding = @embedding_service.embed(search_query)
      return error_response("Failed to generate embedding for question") unless query_embedding

      # 2. Find relevant events
      retrieval_config = @config[:retrieval] || {}
      top_k = retrieval_config[:max_events] || 10
      min_similarity = retrieval_config[:min_similarity] || 0.3

      relevant = @vector_store.search(
        query_embedding,
        user: @user,
        top_k: top_k,
        min_similarity: min_similarity
      )

      return no_context_response if relevant.empty?

      # 3. Build context with configurable max chars
      context_max = retrieval_config[:context_max_chars] || 2000
      context_event_ids = relevant.map { |r| r[:id] }
      context = build_context(context_event_ids, max_chars: context_max)

      # 4. Build messages with history
      messages = build_messages_with_history(question, context, conversation_history)

      # 5. Call AI with context
      response = @ai_client.chat(messages: messages, max_tokens: 2000)

      # 6. Parse and VERIFY citations (include history IDs as valid)
      history_event_ids = extract_history_event_ids(conversation_history)
      all_valid_ids = context_event_ids + history_event_ids
      cited_ids = parse_and_verify_citations(response, all_valid_ids)

      # 7. Load cited events for display
      cited_events = user_events.where(id: cited_ids).includes(source: :user)

      {
        success: true,
        answer: clean_response(response),
        cited_events: cited_events,
        context_event_ids: context_event_ids,
        relevant_scores: relevant
      }
    rescue Rag::EmbeddingService::EmbeddingError => e
      error_response("Embedding service error: #{e.message}")
    rescue Ai::Client::ApiError => e
      error_response("AI service error: #{e.message}")
    end

    def chat_stream(question, conversation_history: [], &block)
      # 0. Rewrite query for better retrieval
      search_query = rewrite_query(question, conversation_history)

      # 1. Embed the rewritten question
      query_embedding = @embedding_service.embed(search_query)
      unless query_embedding
        yield({ type: "error", message: "Failed to generate embedding for question" }.to_json) if block_given?
        return error_response("Failed to generate embedding for question")
      end

      # 2. Find relevant events
      retrieval_config = @config[:retrieval] || {}
      top_k = retrieval_config[:max_events] || 10
      min_similarity = retrieval_config[:min_similarity] || 0.3

      relevant = @vector_store.search(
        query_embedding,
        user: @user,
        top_k: top_k,
        min_similarity: min_similarity
      )

      if relevant.empty?
        no_context_msg = "I couldn't find any relevant content in your library to answer this question."
        yield no_context_msg if block_given?
        return no_context_response
      end

      # 3. Build context
      context_max = retrieval_config[:context_max_chars] || 2000
      context_event_ids = relevant.map { |r| r[:id] }
      context = build_context(context_event_ids, max_chars: context_max)

      # 4. Build messages with history
      messages = build_messages_with_history(question, context, conversation_history)

      # 5. Stream response
      full_response = ""
      @ai_client.chat_stream(messages: messages, max_tokens: 2000) do |chunk|
        full_response += chunk
        yield chunk if block_given?
      end

      # 6. Parse and verify citations (include history IDs as valid)
      history_event_ids = extract_history_event_ids(conversation_history)
      all_valid_ids = context_event_ids + history_event_ids
      cited_ids = parse_and_verify_citations(full_response, all_valid_ids)

      {
        success: true,
        cited_event_ids: cited_ids,
        context_event_ids: context_event_ids
      }
    rescue Rag::EmbeddingService::EmbeddingError => e
      yield({ type: "error", message: "Embedding service error: #{e.message}" }.to_json) if block_given?
      error_response("Embedding service error: #{e.message}")
    rescue Ai::Client::ApiError => e
      raise # Re-raise for controller to handle
    end

    private

    def initialize_query_rewrite_client
      rewrite_config = @config[:query_rewriting] || {}
      return nil unless rewrite_config[:enabled]

      Ai::Client.new(use_case: :query_rewriting)
    end

    def rewrite_query(question, conversation_history)
      return question unless @query_rewrite_client

      # Build context from recent history (last 2 exchanges)
      history_context = Array(conversation_history).last(4).filter_map do |msg|
        next unless msg.respond_to?(:key?)

        role = msg["role"] || msg[:role]
        content = msg["content"] || msg[:content]
        "#{role}: #{content.to_s.truncate(200)}"
      end.join("\n")

      messages = [
        { role: "system", content: QUERY_REWRITE_PROMPT },
        { role: "user", content: "History:\n#{history_context}\n\nQuestion: #{question}" }
      ]

      rewritten = @query_rewrite_client.chat(messages: messages, max_tokens: 1000, temperature: 0.1)
      Rails.logger.info("Query rewritten: '#{question}' → '#{rewritten.strip}'")
      rewritten.strip.presence || question
    rescue => e
      Rails.logger.warn("Query rewriting failed: #{e.message}")
      question # Fall back to original
    end

    # Every event this service is allowed to read or cite. The invariant is that
    # a user only ever sees their own data, so nothing here may widen past it.
    def user_events
      @user.events
    end

    def build_context(event_ids, max_chars:)
      events = user_events.where(id: event_ids).includes(:source)
      events.map do |event|
        content = event.content.to_s.truncate(max_chars)
        source_name = event.source&.name || "Unknown"
        "[EVENT:#{event.id}] (Source: #{source_name})\n#{content}"
      end.join("\n\n---\n\n")
    end

    def build_messages_with_history(question, context, history)
      messages = [{ role: "system", content: SYSTEM_PROMPT }]

      # Add conversation history (previous Q&A pairs)
      Array(history).each do |msg|
        next unless msg.respond_to?(:key?)

        role = msg["role"] || msg[:role]
        content = msg["content"] || msg[:content]
        messages << { role: role, content: content } if role && content
      end

      # Add current question with context
      messages << { role: "user", content: "Context:\n\n#{context}\n\n---\n\nQuestion: #{question}" }
      messages
    end

    def parse_and_verify_citations(response, valid_ids)
      # Parse only inline citations [EVENT:123]
      cited = response.scan(/\[EVENT:(\d+)\]/).flatten.map(&:to_i)

      # VERIFY: Only return IDs that were actually in context
      cited.uniq & valid_ids
    end

    def extract_history_event_ids(conversation_history)
      history_ids = []
      Array(conversation_history).each do |msg|
        next unless msg.respond_to?(:key?)

        role = msg["role"] || msg[:role]
        content = msg["content"] || msg[:content]
        next unless role == "assistant" && content

        # Extract [EVENT:id] references from previous assistant messages
        content.to_s.scan(/\[EVENT:(\d+)\]/).flatten.map(&:to_i).each do |id|
          history_ids << id
        end
      end
      return [] if history_ids.empty?

      # The history comes from the client, so a crafted request could claim any
      # id. Only ids that really belong to this user are treatable as valid.
      user_events.where(id: history_ids.uniq).pluck(:id)
    end

    def clean_response(response)
      # No longer need to remove ---SOURCES--- section
      response.strip
    end

    def no_context_response
      {
        success: true,
        answer: "I couldn't find any relevant content in your library to answer this question. Try asking something related to topics in your indexed events.",
        cited_events: [],
        context_event_ids: [],
        relevant_scores: []
      }
    end

    def error_response(message)
      {
        success: false,
        error: message,
        answer: nil,
        cited_events: [],
        context_event_ids: [],
        relevant_scores: []
      }
    end
  end
end
