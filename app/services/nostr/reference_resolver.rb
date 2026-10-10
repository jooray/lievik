# frozen_string_literal: true

module Nostr
  # Resolves the `nostr:` references inside event content to structured data,
  # local-first (sources, users, events in the DB), then whatever the relay
  # cache holds; a cache miss schedules WarmNostrReferenceCacheJob so the next
  # render has it. One resolver per request: results are memoized, and the same
  # npub/note is typically referenced by many events on one page.
  #
  # Two front ends render the result:
  #   NostrContentHelper#render_nostr_content  HTML links and inline note cards (web)
  #   Api::V1::EventSerializer                 the `references` array (app API)
  #
  # #resolve returns nil for an identifier that does not decode, otherwise one of
  #   { type: :profile, identifier:, npub:, display_name:, url: }
  #   { type: :event,   identifier:, url:, resolved: true,  content:, author_name: }
  #   { type: :event,   identifier:, url:, resolved: false }
  #   { type: :article, identifier:, url:, slug: }
  # `display_name`/`author_name` may be nil; labels (and their translations) are
  # the renderer's job.
  class ReferenceResolver
    PATTERN = /nostr:(nprofile1[a-z0-9]+|npub1[a-z0-9]+|nevent1[a-z0-9]+|note1[a-z0-9]+|naddr1[a-z0-9]+)/i
    PREVIEW_LENGTH = 300

    def initialize(user)
      @user = user
      @cache = {}
    end

    # Unique identifiers (without the "nostr:" prefix) in order of appearance.
    def self.identifiers_in(content)
      return [] if content.blank?

      content.scan(PATTERN).flatten.uniq
    end

    def resolve(identifier)
      return @cache[identifier] if @cache.key?(identifier)

      @cache[identifier] = resolve_uncached(identifier)
    end

    private

    def resolve_uncached(identifier)
      parsed = KeyConverter.parse_nostr_identifier(identifier)
      return nil unless parsed

      case parsed[:type]
      when :nprofile, :npub then resolve_profile(identifier, parsed)
      when :nevent, :note then resolve_event(identifier, parsed)
      when :naddr then resolve_article(identifier, parsed)
      end
    end

    def resolve_profile(identifier, parsed)
      pubkey_hex = parsed[:pubkey]
      return nil unless pubkey_hex

      npub = KeyConverter.hex_to_npub(pubkey_hex)

      # DB lookup first
      source = ::Source.find_by(identifier: npub, source_type: :nostr)
      known_user = ::User.find_by(pubkey_hex: pubkey_hex) unless source
      display_name = source&.name || known_user&.display_name || known_user&.username

      # Then whatever the relay cache holds
      unless display_name.present?
        profile = cached_profile(pubkey_hex, relay_hints: parsed[:relays] || [])
        display_name = profile&.dig(:display_name) || profile&.dig(:username)
      end

      {
        type: :profile,
        identifier: identifier,
        npub: npub,
        display_name: display_name.presence,
        url: @user.profile_url(npub || identifier)
      }
    end

    def resolve_event(identifier, parsed)
      url = @user.event_link_template.gsub("{eventid}", identifier)
      base = { type: :event, identifier: identifier, url: url }

      event = ::Event.find_by(external_id: parsed[:event_id]) if parsed[:event_id]
      if event&.content.present?
        return base.merge(resolved: true, content: event.content.truncate(PREVIEW_LENGTH), author_name: event.source&.name)
      end

      fetched = cached_event(parsed[:event_id], relay_hints: parsed[:relays] || []) if parsed[:event_id]
      if fetched&.dig(:content).present?
        return base.merge(resolved: true, content: fetched[:content].truncate(PREVIEW_LENGTH),
                          author_name: resolve_author_name(fetched[:pubkey]))
      end

      base.merge(resolved: false)
    end

    def resolve_article(identifier, parsed)
      {
        type: :article,
        identifier: identifier,
        slug: parsed[:identifier].presence,
        url: @user.naddr_link_template.gsub("{naddr}", identifier)
      }
    end

    def resolve_author_name(pubkey_hex)
      return nil unless pubkey_hex

      npub = KeyConverter.hex_to_npub(pubkey_hex)
      source = ::Source.find_by(identifier: npub, source_type: :nostr)
      return source.name if source&.name.present?

      known_user = ::User.find_by(pubkey_hex: pubkey_hex)
      return known_user.display_name || known_user.username if known_user

      profile = cached_profile(pubkey_hex)
      profile&.dig(:display_name) || profile&.dig(:username)
    end

    def cached_profile(pubkey_hex, relay_hints: [])
      cached = Rails.cache.read("nostr_profile:#{pubkey_hex}")
      return cached if cached.present?

      schedule_fetch("profile", pubkey_hex, relay_hints: relay_hints)
      nil
    rescue => e
      Rails.logger.warn "Failed to fetch profile #{pubkey_hex}: #{e.message}"
      nil
    end

    def cached_event(event_id_hex, relay_hints: [])
      cached = Rails.cache.read("nostr_event:#{event_id_hex}")
      return cached if cached.present?

      schedule_fetch("event", event_id_hex, relay_hints: relay_hints)
      nil
    rescue => e
      Rails.logger.warn "Failed to fetch event #{event_id_hex}: #{e.message}"
      nil
    end

    def schedule_fetch(reference_type, identifier, relay_hints: [])
      return if identifier.blank?

      schedule_key = "nostr_reference_fetch_scheduled:#{reference_type}:#{identifier}"
      scheduled = Rails.cache.write(schedule_key, true, expires_in: 10.minutes, unless_exist: true)
      return unless scheduled

      WarmNostrReferenceCacheJob.perform_later(reference_type, identifier, Security::EgressGuard.filter_relay_urls(relay_hints))
    rescue => e
      Rails.logger.warn "Failed to schedule #{reference_type} fetch for #{identifier}: #{e.message}"
    end
  end
end
