# frozen_string_literal: true

class RateEventsJob < ApplicationJob
  queue_as :default

  def perform(channel_id, event_ids = nil)
    channel = Channel.find_by(id: channel_id)
    return unless channel

    # Skip if a rating job is already running for this channel
    if ActivityLog.active.where(activity_type: "rating")
        .where("json_extract(metadata, '$.channel_id') = ?", channel.id).exists?
      Rails.logger.info("Skipping rating for #{channel.name} — already running")
      return
    end

    # Get events to rate
    events = if event_ids.present?
      Event.where(id: event_ids)
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

    rating_service = Ai::RatingService.new(channel, activity_log_id: activity_log.id)

    Rails.logger.info("Rating #{total_events} events for channel #{channel.name}")

    begin
      rated_count = 0
      events.find_each.with_index do |event, index|
        result = rating_service.rate_event(event)

        unless result[:error]
          # Create or update channel_event with score
          channel_event = ChannelEvent.find_or_initialize_by(
            channel: channel,
            event: event
          )

          channel_event.update!(
            relevance_score: result[:score],
            relevance_reason: result[:reason]
          )

          rated_count += 1
          Rails.logger.info("Rated event #{event.id} for channel '#{channel.name}': score=#{result[:score]}, reason='#{result[:reason].truncate(200)}'")
        end

        # Update progress every 5 events
        if (index + 1) % 5 == 0 || index + 1 == total_events
          activity_log.update_progress(current: index + 1, total: total_events)
        end
      end

      activity_log.complete!(message: "Rated #{rated_count} events for #{channel.name}")
      Rails.logger.info("Finished rating events for channel #{channel.name}")

      # Re-check: if new events arrived during rating, queue another run.
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
    end
  end
end
