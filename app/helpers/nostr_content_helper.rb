# frozen_string_literal: true

module NostrContentHelper
  NOSTR_URI_PATTERN = /nostr:(nprofile1[a-z0-9]+|npub1[a-z0-9]+|nevent1[a-z0-9]+|note1[a-z0-9]+|naddr1[a-z0-9]+)/i

  def render_nostr_content(content, user: current_user)
    return "" if content.blank?

    escaped = h(content)

    resolved = escaped.gsub(NOSTR_URI_PATTERN) do |match|
      identifier = match.sub(/\Anostr:/i, "")
      resolve_nostr_reference(identifier, user)
    end

    resolved.html_safe
  end

  private

  def resolve_nostr_reference(identifier, user)
    parsed = Nostr::KeyConverter.parse_nostr_identifier(identifier)
    return "nostr:#{identifier}" unless parsed

    case parsed[:type]
    when :nprofile, :npub
      resolve_profile_reference(identifier, parsed, user)
    when :nevent, :note
      resolve_event_reference(identifier, parsed, user)
    when :naddr
      resolve_naddr_reference(identifier, parsed, user)
    else
      "nostr:#{identifier}"
    end
  end

  def resolve_profile_reference(identifier, parsed, user)
    pubkey_hex = parsed[:pubkey]
    return "nostr:#{identifier}" unless pubkey_hex

    npub = Nostr::KeyConverter.hex_to_npub(pubkey_hex)

    # DB lookup first
    source = Source.find_by(identifier: npub, source_type: :nostr)
    known_user = User.find_by(pubkey_hex: pubkey_hex) unless source
    display_name = source&.name || known_user&.display_name || known_user&.username

    # Fetch from relays if not found locally
    unless display_name.present?
      relay_hints = parsed[:relays] || []
      profile = cached_profile(pubkey_hex, relay_hints: relay_hints)
      display_name = profile&.dig(:display_name) || profile&.dig(:username)
    end

    label = display_name.present? ? "@#{display_name}" : "@#{npub&.truncate(20)}"

    url = user.profile_url(npub || identifier)
    link_to(label, url, target: "_blank", rel: "noopener noreferrer",
            class: "text-purple-600 dark:text-purple-400 hover:underline font-medium",
            title: npub)
  end

  def resolve_event_reference(identifier, parsed, user)
    url = user.event_link_template.gsub("{eventid}", identifier)

    # Try local DB first
    event = Event.find_by(external_id: parsed[:event_id]) if parsed[:event_id]

    if event&.content.present?
      author_name = event.source&.name
      render_inline_note_card(event.content, author_name, url, identifier)
    else
      # Try fetching from relays
      fetched = cached_event(parsed[:event_id], relay_hints: parsed[:relays] || []) if parsed[:event_id]
      if fetched&.dig(:content).present?
        author_name = resolve_author_name(fetched[:pubkey])
        render_inline_note_card(fetched[:content], author_name, url, identifier)
      else
        link_to("[referenced note]", url, target: "_blank", rel: "noopener noreferrer",
                class: "text-purple-600 dark:text-purple-400 hover:underline",
                title: identifier)
      end
    end
  end

  def resolve_naddr_reference(identifier, parsed, user)
    url = user.naddr_link_template.gsub("{naddr}", identifier)
    label = parsed[:identifier].present? ? parsed[:identifier].truncate(40) : identifier.truncate(20)
    link_to(label, url, target: "_blank", rel: "noopener noreferrer",
            class: "text-purple-600 dark:text-purple-400 hover:underline",
            title: identifier)
  end

  def render_inline_note_card(content, author_name, url, identifier)
    author_label = author_name.present? ? h(author_name) : "Unknown"
    truncated_content = h(content.truncate(300))

    <<~HTML
      <a href="#{h(url)}" target="_blank" rel="noopener noreferrer" title="#{h(identifier)}"
         class="block border border-gray-200 dark:border-gray-600 rounded-lg p-3 my-2 bg-gray-50 dark:bg-gray-700 hover:bg-gray-100 dark:hover:bg-gray-600 transition-colors no-underline cursor-pointer">
        <span class="text-xs font-medium text-purple-600 dark:text-purple-400">#{author_label}</span>
        <span class="block text-sm text-gray-700 dark:text-gray-200 mt-1 whitespace-pre-wrap">#{truncated_content}</span>
      </a>
    HTML
  end

  def cached_profile(pubkey_hex, relay_hints: [])
    cache_key = "nostr_profile:#{pubkey_hex}"
    cached = Rails.cache.read(cache_key)
    return cached if cached.present?

    schedule_nostr_reference_fetch("profile", pubkey_hex, relay_hints: relay_hints)
    nil
  rescue => e
    Rails.logger.warn "Failed to fetch profile #{pubkey_hex}: #{e.message}"
    nil
  end

  def cached_event(event_id_hex, relay_hints: [])
    cache_key = "nostr_event:#{event_id_hex}"
    cached = Rails.cache.read(cache_key)
    return cached if cached.present?

    schedule_nostr_reference_fetch("event", event_id_hex, relay_hints: relay_hints)
    nil
  rescue => e
    Rails.logger.warn "Failed to fetch event #{event_id_hex}: #{e.message}"
    nil
  end

  def resolve_author_name(pubkey_hex)
    return nil unless pubkey_hex

    npub = Nostr::KeyConverter.hex_to_npub(pubkey_hex)
    source = Source.find_by(identifier: npub, source_type: :nostr)
    return source.name if source&.name.present?

    known_user = User.find_by(pubkey_hex: pubkey_hex)
    return known_user.display_name || known_user.username if known_user

    profile = cached_profile(pubkey_hex)
    profile&.dig(:display_name) || profile&.dig(:username)
  end

  def schedule_nostr_reference_fetch(reference_type, identifier, relay_hints: [])
    return if identifier.blank?

    schedule_key = "nostr_reference_fetch_scheduled:#{reference_type}:#{identifier}"
    scheduled = Rails.cache.write(schedule_key, true, expires_in: 10.minutes, unless_exist: true)
    return unless scheduled

    WarmNostrReferenceCacheJob.perform_later(reference_type, identifier, Array(relay_hints).select(&:present?))
  rescue => e
    Rails.logger.warn "Failed to schedule #{reference_type} fetch for #{identifier}: #{e.message}"
  end
end
