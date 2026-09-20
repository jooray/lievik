# frozen_string_literal: true

module Ai
  # The "decision" rating engine: rates one event for many channels in a single
  # request to a typed-decision model (Jev via Ai::DecisionClient).
  #
  # Shape, and why (benchmarked 2026-09-19 against Ai::RatingService on 512
  # channel/event pairs; see AGENTS.md "Rating engines"):
  #
  # * The event content is the `state`; each channel's criteria go into its
  #   own question's `instructions`. Criteria placed in the state instead were
  #   scored against only loosely — an explicit "Slovak content is low
  #   relevance" rule was ignored there and applied here.
  # * Questions on one state are evaluated independently, so one request can
  #   carry a question per channel: batched vs one-per-request agreed at
  #   Spearman 0.999, and the state is billed once.
  # * The answer is a probability distribution over a 4-level rubric, not
  #   text. The score is the calibrated expected level (Ai::Rating::Calibration)
  #   and the reason is synthesised from the distribution — there is no
  #   written justification, and the model has no world knowledge to speak of
  #   (a bare "#39c3" with images rated 5 where the chat model gave 92).
  class DecisionRatingService
    RUBRIC = [
      "Not relevant for this channel, should be excluded",
      "Low relevance, only tangentially related to the channel criteria",
      "Moderately relevant, could be useful for the channel",
      "Highly relevant, a perfect fit for the channel and its audience"
    ].freeze
    RUBRIC_SHORT = [ "not relevant", "low relevance", "moderately relevant", "highly relevant" ].freeze

    INSTRUCTIONS_PREAMBLE = <<~TEXT.strip
      How relevant is `content` for the following marketing channel? Judge strictly against the channel's relevance criteria, purpose, language and target audience. `author_context` describes the person curating the channel.
    TEXT

    # 64k tokens for state plus all questions; channel prompts run to ~700
    # tokens, content is capped at 2,000 chars, so 40 questions stays well under.
    MAX_QUESTIONS_PER_REQUEST = 40
    MAX_ATTEMPTS = 3
    RETRY_BACKOFF_SECONDS = 2
    MAX_RATE_LIMIT_WAIT = 60

    def initialize(user, activity_log_id: nil, client: nil)
      @user = user
      @activity_log_id = activity_log_id
      @client = client || Ai::DecisionClient.new
    end

    # Returns { channel_id => { score:, reason:, details: } } for every channel
    # given; a channel whose rating failed maps to { score: nil, reason:, error: true }.
    def rate_event(event, channels)
      channels = Array(channels)
      return {} if channels.empty?

      results = {}
      content = Ai::RatingContent.prepare(event)

      ratable = channels.select do |channel|
        if channel.prompt.blank?
          results[channel.id] = { score: 0, reason: "No criteria defined", details: base_details }
          false
        elsif content.blank?
          results[channel.id] = { score: 0, reason: "Empty content", details: base_details }
          false
        else
          true
        end
      end

      state = build_state(content)

      ratable.each_slice(MAX_QUESTIONS_PER_REQUEST) do |slice|
        results.merge!(rate_slice(event, slice, state))
      end

      results
    end

    def rate_event_for_channel(event, channel)
      rate_event(event, [ channel ]).fetch(channel.id)
    end

    private

    def base_details
      { "engine" => "decision", "model" => @client.model }
    end

    # The user's own context minus the generic Lievik preamble — the model
    # scores against what it is given, and boilerplate about what Lievik is
    # only dilutes the state ("context rot").
    def author_context
      text = @user.system_prompt.to_s
      text.split(/\n{2,}/).reject { |p| p.start_with?("You are assisting", "Lievik ingests") }.join("\n\n").strip
    end

    def build_state(content)
      { "author_context" => author_context, "content" => content }
    end

    def channel_block(channel)
      <<~BLOCK.strip
        ## Channel: #{channel.name}
        #{channel.description.present? ? "Description: #{channel.description}" : ""}
        Language: #{channel.language}

        ## Relevance Criteria:
        #{channel.prompt}
      BLOCK
    end

    def question_for(channel)
      {
        "type" => "score",
        "instructions" => "#{INSTRUCTIONS_PREAMBLE}\n\n#{channel_block(channel)}",
        "criteria" => RUBRIC
      }
    end

    def question_id(channel) = "channel_#{channel.id}"

    def rate_slice(event, channels, state)
      questions = channels.to_h { |ch| [ question_id(ch), question_for(ch) ] }
      log_request(event, channels, state, questions)

      attempt = 0
      begin
        attempt += 1
        answers = @client.decide(state: state, questions: questions)
        results = channels.to_h { |ch| [ ch.id, parse_answer(answers.fetch(question_id(ch))) ] }
        log_response(event, channels, answers, results)
        results
      rescue Ai::Client::ApiError => e
        if attempt < MAX_ATTEMPTS
          wait = if e.is_a?(Ai::DecisionClient::RateLimited)
            [ e.retry_after || RETRY_BACKOFF_SECONDS * attempt * 5, MAX_RATE_LIMIT_WAIT ].min
          else
            RETRY_BACKOFF_SECONDS * attempt
          end
          Rails.logger.warn("Decision rating attempt #{attempt}/#{MAX_ATTEMPTS} failed for event #{event.id}: #{e.message} — retrying in #{wait}s")
          sleep(wait)
          retry
        end

        Rails.logger.error("Decision rating failed for event #{event.id} after #{MAX_ATTEMPTS} attempts: #{e.message}")
        log_error(event, channels, e)
        channels.to_h { |ch| [ ch.id, { score: nil, reason: "Rating failed: #{e.message}", error: true } ] }
      end
    end

    # A malformed answer is raised as ApiError so the slice is retried like
    # any other transient failure.
    def parse_answer(answer)
      probs = answer.is_a?(Hash) ? answer["probabilities"] : nil
      raise Ai::DecisionClient::ApiError, "Decision answer has no probabilities" unless probs.is_a?(Hash)

      distribution = RUBRIC.each_index.map do |i|
        p = probs[i.to_s]
        p = Float(p, exception: false) if p.is_a?(String)
        raise Ai::DecisionClient::ApiError, "Decision answer has a non-numeric probability" unless p.is_a?(Numeric)

        p.to_f.clamp(0.0, 1.0)
      end
      total = distribution.sum
      raise Ai::DecisionClient::ApiError, "Decision answer probabilities sum to zero" if total <= 0

      distribution = distribution.map { |p| p / total }
      raw = distribution.each_with_index.sum { |p, i| p * i }
      confidence = answer["confidence"]
      confidence = confidence.is_a?(Numeric) ? confidence.to_f.round(2) : nil

      {
        score: Ai::Rating::Calibration.to_score(raw),
        reason: synthesize_reason(distribution, confidence),
        details: base_details.merge(
          "raw_score" => raw.round(3),
          "probabilities" => distribution.map { |p| p.round(3) },
          "confidence" => confidence,
          "calibration" => Ai::Rating::Calibration::VERSION
        )
      }
    end

    def synthesize_reason(distribution, confidence)
      top = distribution.each_with_index.sort_by { |p, _| -p }.first(2).select { |p, _| p >= 0.1 }
      parts = top.map { |p, i| "#{RUBRIC_SHORT[i]} #{(p * 100).round}%" }
      reason = "Decision model: #{parts.join(', ')}"
      reason += " (confidence #{confidence})" if confidence
      reason.truncate(500)
    end

    def log_request(event, channels, state, questions)
      return unless @activity_log_id

      DevLog.create!(
        user: @user,
        log_type: :ai_request,
        message: "Decision rating event #{event.id} for #{channels.size} channel(s)",
        details: {
          event_id: event.id,
          channel_ids: channels.map(&:id),
          model: @client.model,
          state: state.transform_values { |v| v.to_s.truncate(4000) },
          instructions: questions.transform_values { |q| q["instructions"].truncate(2000) }
        },
        parent_type: "ActivityLog",
        parent_id: @activity_log_id
      )
    end

    def log_response(event, channels, answers, results)
      return unless @activity_log_id

      DevLog.create!(
        user: @user,
        log_type: :ai_response,
        message: "Decision response for event #{event.id}",
        details: {
          event_id: event.id,
          answers: answers.to_json.truncate(4000),
          scores: channels.to_h { |ch| [ ch.id, results[ch.id][:score] ] }
        },
        parent_type: "ActivityLog",
        parent_id: @activity_log_id
      )
    end

    def log_error(event, channels, error)
      return unless @activity_log_id

      DevLog.create!(
        user: @user,
        log_type: :rating_error,
        message: "Decision rating failed: #{error.message}",
        details: { event_id: event.id, channel_ids: channels.map(&:id), error: error.message },
        parent_type: "ActivityLog",
        parent_id: @activity_log_id
      )
    end
  end
end
