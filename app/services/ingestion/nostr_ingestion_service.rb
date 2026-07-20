# frozen_string_literal: true

module Ingestion
  class NostrIngestionService
    # events.content is MEDIUMTEXT on MariaDB (16 MB). Cap well below that so a
    # pathological relay payload can never fail the whole batch on insert.
    MAX_CONTENT_BYTES = 1_000_000
    # d_tag is a varchar(255) lookup key; the untruncated value stays in metadata.
    D_TAG_KEY_LIMIT = 255

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
      rejected_count = 0
      imported_event_ids = []

      new_linked_content_ids = []

      events.each do |event_data|
        # A relay can return anything: forged events attributed to the followed
        # npub, nil created_at/content, wrong types. Reject unverifiable events
        # and make sure a single bad one can never abort the run.
        unless verified_event?(event_data, pubkey_hex)
          rejected_count += 1
          next
        end

        begin
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
        rescue ActiveRecord::RecordNotUnique
          # Concurrent ingestion of the same source imported it first.
          skipped_count += 1
        rescue StandardError => e
          Rails.logger.warn("Skipping bad Nostr event #{event_data['id'].to_s[0, 16]}: #{e.class} - #{e.message}")
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

      Rails.logger.warn("Rejected #{rejected_count} unverifiable Nostr events for #{@source.identifier}") if rejected_count > 0
      Rails.logger.info("Ingestion complete: #{imported_count} imported, #{skipped_count} skipped, #{rejected_count} rejected")

      { success: true, imported: imported_count, skipped: skipped_count, rejected: rejected_count, event_ids: imported_event_ids }
    end

    private

    # SEC-M3: any of the configured public relays can hand back a forged event
    # attributed to a followed npub. Nostr::EventValidator recomputes the id hash
    # and checks the BIP-340 signature; `author:` pins it to this source's pubkey.
    # It also rejects wrong-typed id/pubkey/created_at/kind/tags/content, which is
    # what used to blow up on `Time.at(nil)` and the content NOT NULL constraint.
    def verified_event?(event_data, pubkey_hex)
      Nostr::EventValidator.valid?(event_data, author: pubkey_hex)
    end

    def truncate_content(content)
      return content unless content.is_a?(String)
      return content if content.bytesize <= MAX_CONTENT_BYTES

      Rails.logger.warn("Truncating oversized event content (#{content.bytesize} bytes)")
      content.byteslice(0, MAX_CONTENT_BYTES).scrub("")
    end

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
        reposted = extract_repost_content(event_data)
        # Don't fall back to the raw JSON blob when the embedded event failed
        # verification — drop the repost instead of attributing forged content.
        return nil if reposted == :rejected

        content = reposted || content
      end

      # Determine event type
      event_type = kind_to_event_type(kind, event_data)

      # Create the event
      event = @source.events.create(
        external_id: event_data["id"],
        content: truncate_content(content),
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
      existing_event = find_replaceable_event(d_tag)

      if existing_event
        # Only update if this version is newer
        if event_created_at > existing_event.published_at
          existing_event.update!(
            external_id: event_data["id"],
            content: truncate_content(event_data["content"]),
            published_at: event_created_at,
            raw_data: event_data,
            d_tag: d_tag_key(d_tag),
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
          content: truncate_content(event_data["content"]),
          event_type: :long_form,
          published_at: event_created_at,
          raw_data: event_data,
          d_tag: d_tag_key(d_tag),
          metadata: { "d_tag" => d_tag }
        )
        event.persisted? ? event : nil
      end
    end

    # REL-H5: this used to be `find_by("json_extract(metadata, '$.d_tag') = ?")`.
    # On MariaDB JSON_EXTRACT returns the *quoted* fragment (`"slug"`), so the
    # comparison never matched and every refresh created a duplicate article.
    # JSON_UNQUOTE would fix MariaDB but SQLite (development) has no such
    # function, so lookups go through the indexed d_tag column instead. The
    # column is varchar(255); metadata still holds the untruncated value and is
    # what decides an exact match.
    def find_replaceable_event(d_tag)
      @source.events.where(d_tag: d_tag_key(d_tag)).detect { |e| e.metadata&.dig("d_tag") == d_tag }
    end

    def d_tag_key(d_tag)
      d_tag.to_s[0, D_TAG_KEY_LIMIT]
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
        # SEC-M3: the embedded event is relay-supplied JSON with its own author.
        # Verify id + signature before we attribute the content to anyone (no
        # `author:` pin here — the original poster is someone other than the
        # reposter by definition).
        unless Nostr::EventValidator.valid?(original)
          Rails.logger.warn("Rejected unverifiable reposted event inside #{event_data['id'].to_s[0, 16]}")
          return :rejected
        end

        original["content"]
      rescue JSON::ParserError
        nil
      end
    end
  end
end
