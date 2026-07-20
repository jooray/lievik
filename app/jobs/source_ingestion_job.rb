# frozen_string_literal: true

class SourceIngestionJob < ApplicationJob
  queue_as :default

  # The 30-minute recurring refresh, the manual refresh buttons, the MCP
  # refresh_source tool and a slow previous run can all target the same source at
  # once, and the check-then-create in the ingestion services then races into
  # RecordNotUnique. A cache lock (same pattern as Nip46SupervisorJob) keeps one
  # run per source; the TTL means a crashed worker can't wedge the source.
  LOCK_TTL = 30.minutes

  def self.lock_key(source_id)
    "source-ingestion-lock:#{source_id}"
  end

  def perform(source_id)
    source = Source.find_by(id: source_id)
    return unless source

    key = self.class.lock_key(source_id)
    token = SecureRandom.hex(16)
    unless Rails.cache.write(key, token, unless_exist: true, expires_in: LOCK_TTL)
      Rails.logger.info("SourceIngestionJob skipped: source #{source_id} is already being ingested")
      return
    end

    begin
      ingest(source)
    ensure
      Rails.cache.delete(key) if Rails.cache.read(key) == token
    end
  end

  private

  def ingest(source)
    activity_log = ActivityLog.start_activity(
      user: source.user,
      activity_type: "ingestion",
      message: "Ingesting from #{source.name || source.identifier.truncate(20)}",
      metadata: { source_id: source.id }
    )

    begin
      result = case source.source_type
      when "nostr"
        Ingestion::NostrIngestionService.new(source, activity_log_id: activity_log.id).ingest
      when "rss"
        Ingestion::RssIngestionService.new(source, activity_log_id: activity_log.id).ingest
      end

      if result && result[:success]
        if result[:imported] > 0
          activity_log.complete!(message: "Ingested #{result[:imported]} events from #{source.name || source.identifier.truncate(20)}")

          # Queue rating for all user channels only if new events were imported
          source.user.channels.find_each do |channel|
            RateEventsJob.perform_later(channel.id)
          end

          # Queue embedding generation for new events
          if result[:event_ids].present?
            EmbedEventsJob.perform_later(result[:event_ids])
          end
        else
          # Don't log when nothing was ingested
          activity_log.destroy
        end
      else
        activity_log.fail!(message: result&.dig(:error) || "Ingestion failed")
      end
    rescue StandardError => e
      activity_log.fail!(message: e.message)
      raise
    end
  end
end
