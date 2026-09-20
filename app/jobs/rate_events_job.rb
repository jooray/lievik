# frozen_string_literal: true

class RateEventsJob < ApplicationJob
  queue_as :default

  # Rating an event costs up to 3 paid AI calls, so bulk work is bounded twice:
  #
  # * BATCH_SIZE — an explicit id list is split into chunks and enqueued as one
  #   job per chunk. Keeps the serialized job payload small (a 50k-id array is
  #   multiple MB in the queue table) and limits the blast radius of a failure
  #   to a single chunk instead of the whole batch.
  # * MAX_BULK_RATE_EVENTS — absolute cap on how many events a single user
  #   request may queue. Enforced by the callers (controllers), which tell the
  #   user how many were queued and how many were skipped.
  BATCH_SIZE = 50
  MAX_BULK_RATE_EVENTS = 2_000

  # Upper bound on how long the unrated-path lock is held if a worker dies
  # without releasing it.
  LOCK_TTL = 30.minutes

  # Enqueue rating for an explicit set of event ids, chunked into BATCH_SIZE
  # jobs. Returns the number of ids queued.
  def self.enqueue_batches(channel_id, event_ids)
    ids = Array(event_ids).compact.uniq
    return 0 if ids.empty?

    ids.each_slice(BATCH_SIZE) { |chunk| perform_later(channel_id, chunk) }
    ids.size
  end

  def perform(channel_id, event_ids = nil)
    channel = Channel.find_by(id: channel_id)
    return unless channel

    ids = Array(event_ids).compact.uniq

    # Safety net for jobs enqueued elsewhere (or before chunking existed) with a
    # huge id array: re-split into chunks instead of processing it all here.
    if ids.size > BATCH_SIZE
      Rails.logger.info("Splitting #{ids.size} event ids into #{BATCH_SIZE}-event batches for #{channel.name}")
      self.class.enqueue_batches(channel.id, ids)
      return
    end

    # Skip if a rating job is already running for this channel.
    #
    # This guard applies only to the "rate whatever is unrated" path — that job
    # is queued from several places and re-queues itself, so overlapping runs
    # would duplicate work. Explicit id batches are distinct chunks of one
    # user request; skipping them would silently drop events from the batch.
    #
    # The claim is an atomic cache write rather than an ActivityLog existence
    # check: check-then-act let two workers both pass the check and then race on
    # the channel_events unique index, killing one job mid-batch.
    if ids.empty?
      lock_token = SecureRandom.hex(16)
      unless claim_lock(channel.id, lock_token)
        Rails.logger.info("Skipping rating for #{channel.name} — already running")
        return
      end
    end

    begin
      rate_events(channel, ids)
    ensure
      release_lock(channel.id, lock_token) if lock_token
    end
  end

  private

  def lock_key(channel_id) = "rate-events-job:channel:#{channel_id}"

  def claim_lock(channel_id, token)
    Rails.cache.write(lock_key(channel_id), token, unless_exist: true, expires_in: LOCK_TTL)
  end

  def release_lock(channel_id, token)
    key = lock_key(channel_id)
    Rails.cache.delete(key) if Rails.cache.read(key) == token
  end

  def rate_events(channel, ids)
    # Get events to rate
    events = if ids.present?
      channel.user.events.where(id: ids)
    else
      # Rate unrated events for this channel
      unrated_event_ids = channel.user.sources
        .joins(:events)
        .where.not(events: { id: channel.events.select(:id) })
        .select("events.id")

      Event.where(id: unrated_event_ids).limit(50)
    end

    total_events = events.count
    return if total_events.zero?

    activity_log = ActivityLog.start_activity(
      user: channel.user,
      activity_type: "rating",
      message: "Rating #{total_events} events for #{channel.name}",
      metadata: { channel_id: channel.id, total: total_events }
    )

    Rails.logger.info("Rating #{total_events} events for channel #{channel.name} (#{channel.user.decision_rating? ? 'decision' : 'chat'} engine)")

    begin
      rated_count, cancelled = if channel.user.decision_rating?
        rate_with_decision_engine(channel, events, total_events, activity_log)
      else
        rate_with_chat_engine(channel, events, total_events, activity_log)
      end

      # A cancelled log is already in its final state — don't overwrite the
      # user's "Cancelled" with "completed", and don't chain a follow-up run.
      if cancelled
        Rails.logger.info("Stopped rating for #{channel.name} — cancelled by user")
        return
      end

      activity_log.complete!(message: "Rated #{rated_count} events for #{channel.name}")
      Rails.logger.info("Finished rating events for channel #{channel.name}")

      # Re-check: if new events arrived during rating, queue another run.
      # Only for the "unrated" path — an explicit batch is one chunk of a larger
      # user request whose other chunks are already queued; chaining from every
      # chunk would multiply the follow-up jobs by the number of chunks.
      return if ids.present?

      # Only re-queue when this run actually rated something — otherwise events
      # that consistently fail (e.g. the AI returns no content) would re-queue
      # forever, hammering the API. A run that rates zero events ends the chain.
      remaining = channel.user.sources
        .joins(:events)
        .where.not(events: { id: channel.events.select(:id) })
        .count
      if remaining > 0 && rated_count > 0
        Rails.logger.info("#{remaining} unrated events remain for #{channel.name} — queueing follow-up")
        RateEventsJob.perform_later(channel.id)
      elsif remaining > 0
        Rails.logger.warn("#{remaining} unrated events remain for #{channel.name} but none could be rated this run — not re-queueing")
      end
    rescue StandardError => e
      activity_log.fail!(message: e.message)
      raise
    ensure
      # See SourceIngestionJob: a worker interrupted mid-run (deploy, restart,
      # crash loop) unwinds without raising a StandardError, which would strand
      # this log as a permanent "running" card. Must never raise itself.
      begin
        if activity_log.persisted? && activity_log.reload.active?
          activity_log.fail!(message: "Interrupted — worker stopped mid-run")
        end
      rescue ActiveRecord::RecordNotFound, ActiveRecord::ActiveRecordError
        nil
      end
    end
  end

  # One chat completion per channel/event pair (Ai::RatingService).
  def rate_with_chat_engine(channel, events, total_events, activity_log)
    rating_service = Ai::RatingService.new(channel, activity_log_id: activity_log.id)
    rated_count = 0

    events.find_each.with_index do |event, index|
      return [ rated_count, true ] if cancelled?(activity_log, channel, rated_count)

      result = rating_service.rate_event(event)

      unless result[:error]
        channel_event = find_or_create_channel_event(channel, event)

        channel_event.update!(
          relevance_score: result[:score],
          relevance_reason: result[:reason],
          rating_details: result[:details]
        )

        rated_count += 1
        Rails.logger.info("Rated event #{event.id} for channel '#{channel.name}': score=#{result[:score]}, reason='#{result[:reason].truncate(200)}'")
      end

      report_progress(activity_log, index, total_events)
    end

    [ rated_count, false ]
  end

  # One decision request per event, carrying a question for this channel AND
  # every other channel of the user that has no rating for the event yet
  # (Ai::DecisionRatingService). The state (event content) is billed once per
  # request, so rating an event for 40 channels costs about the same as for
  # one, and the per-key request limit is spent per event rather than per
  # pair. Sibling ratings are only ever *added*, never overwritten, so an
  # explicit re-rate of this channel leaves the others alone.
  def rate_with_decision_engine(channel, events, total_events, activity_log)
    rating_service = Ai::DecisionRatingService.new(channel.user, activity_log_id: activity_log.id)
    rated_count = 0

    events.find_each.with_index do |event, index|
      return [ rated_count, true ] if cancelled?(activity_log, channel, rated_count)

      channels = [ channel ] + sibling_channels_missing_rating(channel, event)
      results = rating_service.rate_event(event, channels)

      channels.each do |target|
        result = results[target.id]
        next if result.nil? || result[:error]

        channel_event = find_or_create_channel_event(target, event)
        next if target.id != channel.id && channel_event.relevance_score.present?

        channel_event.update!(
          relevance_score: result[:score],
          relevance_reason: result[:reason],
          rating_details: result[:details]
        )

        if target.id == channel.id
          rated_count += 1
          Rails.logger.info("Rated event #{event.id} for channel '#{channel.name}' (+#{channels.size - 1} sibling channel(s)): score=#{result[:score]}")
        end
      end

      report_progress(activity_log, index, total_events)
    end

    [ rated_count, false ]
  end

  # Re-rating an existing pair must update it, and a concurrent run may insert
  # the pair between our lookup and our insert. `create_or_find_by!` cannot do
  # this here: ChannelEvent validates uniqueness, so an existing pair raises
  # RecordInvalid (which it does not rescue) before the unique index ever
  # gets to raise RecordNotUnique.
  def find_or_create_channel_event(channel, event)
    ChannelEvent.find_or_create_by!(channel: channel, event: event)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    ChannelEvent.find_by!(channel: channel, event: event)
  end

  def sibling_channels_missing_rating(channel, event)
    channel.user.channels
      .where.not(id: channel.id)
      .where.not(prompt: [ nil, "" ])
      .where.not(id: ChannelEvent.where(event_id: event.id).select(:channel_id))
      .order(:id)
      .to_a
  end

  # "Cancel" in the UI only flips the flag; without this check the job kept
  # burning paid AI calls and then flipped the log back to "completed".
  def cancelled?(activity_log, channel, rated_count)
    return false if activity_log.reload.active?

    Rails.logger.info("Rating for #{channel.name} cancelled after #{rated_count} events")
    true
  end

  # Update progress every 5 events
  def report_progress(activity_log, index, total_events)
    if (index + 1) % 5 == 0 || index + 1 == total_events
      activity_log.update_progress(current: index + 1, total: total_events)
    end
  end
end
