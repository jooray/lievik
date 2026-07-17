# frozen_string_literal: true

module Ingestion
  class NostrIngestionService
    def initialize(source, activity_log_id: nil)
      @source = source
      @user = source.user
      @activity_log_id = activity_log_id
    end

    def ingest
      return { success: false, error: "Source is not a Nostr source" } unless @source.nostr?

      pubkey_hex = normalize_pubkey(@source.identifier)
      return { success: false, error: "Invalid pubkey" } unless pubkey_hex

      settings = @source.settings
      import_days = settings["import_days"] || 30
      since_time = import_days.days.ago

      Rails.logger.info("Ingesting Nostr events for #{@source.name || pubkey_hex[0..7]}...")

      fetcher = Nostr::EventFetcher.new
      events = fetcher.fetch(pubkey_hex,
        since: since_time,
        include_replies: settings["include_replies"],
        include_reposts: settings["include_reposts"],
        limit: 500
      )

      imported_count = 0
      skipped_count = 0
      imported_event_ids = []

      new_linked_content_ids = []

      events.each do |event_data|
        result = import_event(event_data)
        if result
          imported_count += 1
          imported_event_ids << result.id
          # Extract links from the new event
          linked_contents = Links::ExtractionService.new(result).extract_and_save
          new_linked_content_ids.concat(linked_contents.select { |lc| lc.fetched_at.nil? }.map(&:id))
        else
          skipped_count += 1
        end
      end

      # Queue link fetching job if there are new links
      if new_linked_content_ids.any?
        FetchLinksJob.perform_later(new_linked_content_ids.uniq)
      end

      # Update source metadata if needed
      if @source.name.blank?
        profile = Nostr::ProfileFetcher.new.fetch(pubkey_hex)
        if profile
          @source.update(
            name: profile[:display_name] || profile[:username],
            description: @source.description.presence || profile[:about]
          )
        end
      end

      @source.update(last_fetched_at: Time.current) if @source.respond_to?(:last_fetched_at)

      Rails.logger.info("Ingestion complete: #{imported_count} imported, #{skipped_count} skipped")

      { success: true, imported: imported_count, skipped: skipped_count, event_ids: imported_event_ids }
    end

    private

    def normalize_pubkey(identifier)
      if identifier.start_with?("npub")
        Nostr::KeyConverter.npub_to_hex(identifier)
      elsif identifier.match?(/\A[0-9a-f]{64}\z/i)
        identifier.downcase
      end
    end

    def import_event(event_data)
      kind = event_data["kind"]

      # Kind 30023 (long-form content) is a parameterized replaceable event
      # Only keep the latest version for each d-tag
      if kind == 30023
        return import_replaceable_event(event_data)
      end

      # Check if event already exists (for regular events)
      return nil if @source.events.exists?(external_id: event_data["id"])

      content = event_data["content"]

      # For reposts (kind 6), try to get the original content
      if kind == 6
        content = extract_repost_content(event_data) || content
      end

      # Determine event type
      event_type = kind_to_event_type(kind, event_data)

      # Create the event
      event = @source.events.create(
        external_id: event_data["id"],
        content: content,
        event_type: event_type,
        published_at: Time.at(event_data["created_at"]),
        raw_data: event_data
      )

      event.persisted? ? event : nil
    end

    # Import a parameterized replaceable event (kind 30023 long-form content)
    # These events are identified by their d-tag, not event ID
    # Only the most recent version (by created_at) should be kept
    def import_replaceable_event(event_data)
      d_tag = extract_d_tag(event_data)
      return nil if d_tag.blank? # Invalid long-form content without d-tag

      event_created_at = Time.at(event_data["created_at"])

      # Check if we already have this article (same source + d-tag)
      # Store d-tag in metadata for lookup
      existing_event = @source.events.find_by("json_extract(metadata, '$.d_tag') = ?", d_tag)

      if existing_event
        # Only update if this version is newer
        if event_created_at > existing_event.published_at
          existing_event.update!(
            external_id: event_data["id"],
            content: event_data["content"],
            published_at: event_created_at,
            raw_data: event_data,
            metadata: (existing_event.metadata || {}).merge("d_tag" => d_tag)
          )
          return existing_event
        else
          # Older version, skip
          return nil
        end
      else
        # New article, create it
        event = @source.events.create(
          external_id: event_data["id"],
          content: event_data["content"],
          event_type: :long_form,
          published_at: event_created_at,
          raw_data: event_data,
          metadata: { "d_tag" => d_tag }
        )
        event.persisted? ? event : nil
      end
    end

    def extract_d_tag(event_data)
      tags = event_data["tags"] || []
      d_tag_entry = tags.find { |t| t[0] == "d" }
      d_tag_entry&.at(1)
    end

    def kind_to_event_type(kind, event_data)
      case kind
      when 6 then :repost
      when 30023 then :long_form
      else
        # Check if it's a reply (has 'e' tag)
        if event_data["tags"]&.any? { |t| t[0] == "e" }
          :reply
        else
          :original
        end
      end
    end

    def extract_repost_content(event_data)
      # Kind 6 reposts often have the original event in content as JSON
      return nil if event_data["content"].blank?

      begin
        original = JSON.parse(event_data["content"])
        original["content"]
      rescue JSON::ParserError
        nil
      end
    end
  end
end
