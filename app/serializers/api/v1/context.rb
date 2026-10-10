# frozen_string_literal: true

module Api
  module V1
    # Per-request state for the serializers: the user (link templates), one
    # Nostr::ReferenceResolver (memoized lookups, shared with the web helper's
    # logic) and the author pictures preloaded for a batch of events.
    class Context
      attr_reader :user, :resolver

      def initialize(user)
        @user = user
        @resolver = Nostr::ReferenceResolver.new(user)
        @authors = {}
      end

      def self.iso(time)
        time&.utc&.iso8601
      end

      # Loads names/pictures for the pubkeys of these events in two queries
      # (registered Lievik users, then the relay profile cache) instead of one
      # per event.
      def preload_authors(events)
        pubkeys = events.filter_map { |e| author_pubkey(e) }.uniq - @authors.keys
        return if pubkeys.empty?

        users = User.where(pubkey_hex: pubkeys).pluck(:pubkey_hex, :picture_url).to_h
        cached = Rails.cache.read_multi(*pubkeys.map { |pk| "nostr_profile:#{pk}" })
        pubkeys.each do |pk|
          profile = cached["nostr_profile:#{pk}"]
          picture = users[pk].presence || (profile.is_a?(Hash) ? profile[:picture] : nil)
          @authors[pk] = { picture_url: safe_url(picture) }
        end
      end

      def author_for(event)
        source = event.source
        pubkey = author_pubkey(event)
        unless pubkey
          return { name: source&.display_label, picture_url: nil, npub: nil }
        end

        preload_authors([ event ]) unless @authors.key?(pubkey)
        {
          name: source&.display_label,
          picture_url: @authors.dig(pubkey, :picture_url),
          npub: Nostr::KeyConverter.hex_to_npub(pubkey)
        }
      end

      # http(s) only: feed/relay-supplied URLs must never reach the client as a
      # javascript: or file: link.
      def safe_url(url)
        return nil if url.blank?

        uri = URI.parse(url.to_s.strip)
        (uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)) && uri.host.present? ? uri.to_s : nil
      rescue URI::InvalidURIError
        nil
      end

      private

      def author_pubkey(event)
        return nil unless event.source&.nostr?

        pubkey = event.raw_data.is_a?(Hash) ? event.raw_data["pubkey"] : nil
        pubkey.is_a?(String) && pubkey.match?(/\A[0-9a-f]{64}\z/i) ? pubkey.downcase : nil
      end
    end
  end
end
