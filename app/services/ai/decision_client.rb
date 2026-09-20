# frozen_string_literal: true

module Ai
  # Client for typed-decision ("System One") endpoints: TypeSafe's Jev, resold
  # by Venice as `jev-latest` behind `POST /decisions`. Unlike Ai::Client this
  # is not a chat API — it takes a `state` and a map of typed questions and
  # returns probability distributions, never text. See
  # Ai::DecisionRatingService for how ratings are built on top of it.
  #
  # Errors are raised as Ai::Client::ApiError subclasses so callers that already
  # rescue the chat client's errors keep working.
  class DecisionClient
    class ApiError < Ai::Client::ApiError; end
    class ConfigurationError < ApiError; end

    class RateLimited < ApiError
      attr_reader :retry_after

      def initialize(message, retry_after: nil)
        super(message)
        @retry_after = retry_after
      end
    end

    # Venice allows 100 /decisions requests per minute per key and, after more
    # than 50 non-success responses, refuses everything for 30 s. Keep every
    # request in this process at least this far apart so a burst of parallel
    # jobs cannot trip that lock. (Shared across worker threads; Solid Queue
    # runs in-process here.)
    MIN_REQUEST_INTERVAL = 0.65
    ERROR_BODY_LIMIT = 500

    @pace_mutex = Mutex.new
    @next_request_at = 0.0

    class << self
      def config
        Ai::Client.ai_config.fetch(:decision, {}).deep_symbolize_keys
      end

      def api_key
        ENV["DECISION_API_KEY"].presence || ENV["VENICE_API_KEY"].presence
      end

      def configured?
        cfg = config
        cfg[:endpoint].present? && cfg[:model].present? && api_key.present?
      end

      def model
        config[:model]
      end

      def throttle
        @pace_mutex.synchronize do
          wait = @next_request_at - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          sleep(wait) if wait.positive?
          @next_request_at = [ Process.clock_gettime(Process::CLOCK_MONOTONIC), @next_request_at ].max + MIN_REQUEST_INTERVAL
        end
      end
    end

    def initialize(config = nil)
      @config = (config || self.class.config).deep_symbolize_keys
      @endpoint = @config[:endpoint]
      @model = @config[:model]
      @api_key = self.class.api_key
    end

    attr_reader :model

    # state:     String, Hash or Array — serialised into the model's context.
    # questions: { "id" => { type: "score"|"noul"|"choice", instructions:, criteria: } }
    # Returns the `answers` hash keyed by the same ids.
    def decide(state:, questions:)
      ensure_configured!
      raise ArgumentError, "questions must not be empty" if questions.blank?

      self.class.throttle

      response = http_client.post(
        "#{@endpoint}/decisions",
        json: { model: @model, state: state, questions: questions }
      )

      handle_response(response, questions.keys.map(&:to_s))
    end

    private

    def ensure_configured!
      raise ConfigurationError, "Decision endpoint is not configured" if @endpoint.blank?
      raise ConfigurationError, "Decision model is not configured" if @model.blank?
      raise ConfigurationError, "Decision API key is not configured" if @api_key.blank?
    end

    def http_client
      @http_client ||= HTTPX.with(
        headers: { "Content-Type" => "application/json", "Authorization" => "Bearer #{@api_key}" },
        timeout: { connect_timeout: 30, read_timeout: 120, write_timeout: 30, request_timeout: 120 }
      )
    end

    def handle_response(response, expected_ids)
      if response.is_a?(HTTPX::ErrorResponse)
        raise ApiError, "Connection failed: #{response.error.message}"
      end

      if response.status == 429
        retry_after = response.headers["retry-after"].to_s.to_f
        raise RateLimited.new("Decision API rate limited (429): #{redact(response.body)}",
                              retry_after: retry_after.positive? ? retry_after : nil)
      end

      unless response.status == 200
        raise ApiError, "Decision API request failed (#{response.status}): #{redact(response.body)}"
      end

      data = JSON.parse(response.body.to_s)
      answers = data["answers"]
      raise ApiError, "Decision API response has no answers: #{redact(response.body)}" unless answers.is_a?(Hash)

      missing = expected_ids - answers.keys
      raise ApiError, "Decision API response missing answers for #{missing.join(', ')}" if missing.any?

      answers
    rescue JSON::ParserError => e
      raise ApiError, "Decision API returned invalid JSON: #{e.message}"
    end

    # Error bodies may echo the state (note content); keep logs short.
    def redact(body)
      text = body.to_s.gsub(/\s+/, " ").strip
      return "(empty)" if text.empty?

      text = text.gsub(/"(state|questions)"\s*:\s*(\{.*?\}|\[.*?\]|".*?")/m, '"\1":"[redacted]"')
      text.truncate(ERROR_BODY_LIMIT)
    end
  end
end
