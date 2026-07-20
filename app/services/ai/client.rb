# frozen_string_literal: true

require "net/http"
require "openssl"
require "uri"

module Ai
  class Client
    class ApiError < StandardError; end
    class ConfigurationError < ApiError; end

    def self.ai_config
      Rails.application.config_for(:lievik).fetch(:ai, {}).deep_symbolize_keys
    end

    def self.model_for(use_case, config: nil)
      return nil if use_case.blank?

      resolved_config = (config || ai_config()).deep_symbolize_keys
      resolved_config.dig(:models, use_case.to_sym)
    end

    def initialize(config = nil, model: nil, use_case: nil)
      @config = (config || self.class.ai_config).deep_symbolize_keys
      @endpoint = @config[:endpoint]
      @model = model || self.class.model_for(use_case, config: @config)
      @api_key = ENV["VENICE_API_KEY"] || ENV["OPENAI_API_KEY"]
    end

    def chat(messages:, temperature: 0.3, max_tokens: 1000)
      ensure_configured!

      response = http_client.post(
        "#{@endpoint}/chat/completions",
        json: request_payload(
          model: @model,
          messages: messages,
          temperature: temperature,
          max_tokens: max_tokens
        )
      )

      handle_response(response)
    end

    # True streaming using Net::HTTP
    def chat_stream(messages:, temperature: 0.3, max_tokens: 1000, &block)
      ensure_configured!

      uri = URI.parse("#{@endpoint}/chat/completions")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = 300
      http.open_timeout = 30

      request = Net::HTTP::Post.new(uri.path)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{@api_key}" if @api_key.present?

      request.body = request_payload(
          model: @model,
          messages: messages,
          temperature: temperature,
          max_tokens: max_tokens,
          stream: true
      ).to_json

      buffer = +""
      content_chars = 0
      finish_reason = nil
      last_event = nil

      http.request(request) do |response|
        unless response.code == "200"
          error_body = response.body rescue "Unknown error"
          raise ApiError, "API request failed (#{response.code}): #{redact_error_body(error_body)}"
        end

        response.read_body do |chunk|
          buffer << chunk

          # A server that never sends an event separator would otherwise grow the
          # buffer without bound; drop what can no longer be a valid SSE event.
          if buffer.bytesize > MAX_SSE_BUFFER_BYTES
            Rails.logger.warn("AI streaming buffer exceeded #{MAX_SSE_BUFFER_BYTES} bytes (model=#{@model}); discarding partial event")
            buffer = +""
            next
          end

          # SSE events are separated by blank lines (\n\n)
          # This correctly handles newlines within JSON content
          while (event_end = buffer.index("\n\n"))
            event_data = buffer.slice!(0, event_end + 2)

            # Parse event data (may have multiple "data:" lines for multi-line content)
            data_lines = event_data.lines.select { |l| l.start_with?("data:") }
            data = data_lines.map { |l| l.sub(/^data:\s?/, "").chomp }.join("\n")

            next if data.empty? || data == "[DONE]"

            begin
              parsed = JSON.parse(data)
              last_event = data
              finish_reason ||= parsed.dig("choices", 0, "finish_reason")
              delta = parsed.dig("choices", 0, "delta") || {}
              content = delta["content"]
              reasoning_content = delta["reasoning_content"]

              if content.nil? && !reasoning_content.nil?
                yield "" if block_given?
                next
              end

              # Use nil check instead of present? to preserve whitespace-only chunks (newlines)
              if !content.nil?
                content_chars += content.length
                yield content if block_given?
              end
            rescue JSON::ParserError
              # Skip invalid JSON lines
            end
          end
        end
      end

      if content_chars.zero?
        Rails.logger.error(
          "AI empty streaming response (model=#{@model}, finish_reason=#{finish_reason.inspect}): " \
          "last_event=#{redact_error_body(last_event)}"
        )
      end
    rescue *NETWORK_ERRORS => e
      # Callers only handle ApiError; a raw Errno/Timeout would bypass them.
      raise ApiError, "Connection failed: #{e.class} - #{e.message}"
    end

    private

    # SSE events are tiny; anything past this is a server that never terminated an
    # event, so we drop the partial instead of growing the buffer forever.
    MAX_SSE_BUFFER_BYTES = 1_000_000

    NETWORK_ERRORS = [
      Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH, Errno::ENETUNREACH, Errno::EPIPE,
      SocketError, IOError, EOFError,
      Net::OpenTimeout, Net::ReadTimeout, Net::HTTPBadResponse, Net::ProtocolError,
      OpenSSL::SSL::SSLError
    ].freeze

    # Error bodies can echo back the submitted prompt; keep logs short and drop
    # anything that looks like the request payload we sent.
    ERROR_BODY_LIMIT = 500

    def redact_error_body(body)
      text = body.to_s.gsub(/\s+/, " ").strip
      return "(empty)" if text.empty?
      text = text.gsub(/"(messages|prompt|input)"\s*:\s*(\[.*?\]|".*?")/m, '"\1":"[redacted]"')
      text.truncate(ERROR_BODY_LIMIT)
    end

    def ensure_configured!
      raise ConfigurationError, "AI endpoint is not configured" if @endpoint.blank?
      raise ConfigurationError, "AI model is not configured" if @model.blank?
    end

    def request_payload(payload)
      normalized_payload(payload).merge(provider_specific_payload)
    end

    # Venice reasoning models (claude-sonnet-4-6, deepseek-v4-flash, …) always
    # emit reasoning tokens, and those tokens count against the completion
    # budget. With a tight max_tokens the reasoning can consume the entire
    # allowance, leaving an EMPTY response with finish_reason: "length" — this
    # was silently dropping ratings (a small classification budget is far less
    # than the reasoning overhead). Add headroom so the caller's
    # intended output size survives the reasoning overhead, strip the thinking
    # from the returned content, and keep the effort low to limit the overhead.
    REASONING_HEADROOM_TOKENS = 8_000
    MODEL_MAX_COMPLETION_TOKENS = 64_000
    VENICE_REASONING_MODELS = %w[claude-sonnet-4-6 deepseek-v4-flash].freeze

    def venice_reasoning_model?
      @config[:provider].to_s == "venice" && VENICE_REASONING_MODELS.include?(@model)
    end

    def normalized_payload(payload)
      normalized = payload.dup

      if venice_reasoning_model? && normalized.key?(:max_tokens)
        requested = normalized.delete(:max_tokens)
        normalized[:max_completion_tokens] =
          [requested + REASONING_HEADROOM_TOKENS, MODEL_MAX_COMPLETION_TOKENS].min
      end

      normalized
    end

    def provider_specific_payload
      return {} unless venice_reasoning_model?

      {
        venice_parameters: {
          strip_thinking_response: true
        },
        reasoning: {
          effort: "low"
        }
      }
    end

    def http_client
      headers = { "Content-Type" => "application/json" }
      headers["Authorization"] = "Bearer #{@api_key}" if @api_key.present?

      @http_client ||= HTTPX.plugin(:retries)
        .with(
          headers: headers,
          timeout: {
            connect_timeout: 30,
            read_timeout: 300,
            write_timeout: 60,
            request_timeout: 300
          }
        )
    end

    def handle_response(response)
      # Handle HTTPX errors (connection failures, timeouts, etc.)
      if response.is_a?(HTTPX::ErrorResponse)
        raise ApiError, "Connection failed: #{response.error.message}"
      end

      unless response.status == 200
        raise ApiError, "API request failed (#{response.status}): #{redact_error_body(response.body)}"
      end

      data = JSON.parse(response.body.to_s)
      content = data.dig("choices", 0, "message", "content")

      if content.blank?
        finish_reason = data.dig("choices", 0, "finish_reason")
        Rails.logger.error(
          "AI empty response (model=#{@model}, finish_reason=#{finish_reason.inspect}): " \
          "#{redact_error_body(response.body)}"
        )
        raise ApiError, "No content in response (finish_reason=#{finish_reason})"
      end

      content
    end
  end
end
