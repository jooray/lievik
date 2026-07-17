# frozen_string_literal: true

class WarmNostrReferenceCacheJob < ApplicationJob
  queue_as :default

  def perform(reference_type, identifier, relay_hints = [])
    relay_hints = Array(relay_hints).select(&:present?)

    case reference_type
    when "profile"
      warm_profile(identifier, relay_hints)
    when "event"
      warm_event(identifier, relay_hints)
    else
      Rails.logger.warn("Unknown Nostr reference type: #{reference_type}")
    end
  ensure
    Rails.cache.delete(schedule_key(reference_type, identifier)) if identifier.present?
  end

  private

  def warm_profile(pubkey_hex, relay_hints)
    return if pubkey_hex.blank?

    cache_key = "nostr_profile:#{pubkey_hex}"
    return if Rails.cache.exist?(cache_key)

    profile = Nostr::ProfileFetcher.new.fetch(pubkey_hex, relay_hints: relay_hints)
    Rails.cache.write(cache_key, profile, expires_in: 1.day) if profile.present?
  end

  def warm_event(event_id_hex, relay_hints)
    return if event_id_hex.blank?

    cache_key = "nostr_event:#{event_id_hex}"
    return if Rails.cache.exist?(cache_key)

    event = Nostr::ProfileFetcher.new.fetch_event(event_id_hex, relay_hints: relay_hints)
    Rails.cache.write(cache_key, event, expires_in: 1.day) if event.present?
  end

  def schedule_key(reference_type, identifier)
    "nostr_reference_fetch_scheduled:#{reference_type}:#{identifier}"
  end
end
