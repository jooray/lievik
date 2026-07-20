# frozen_string_literal: true

require "json"
require "securerandom"

module Nostr
  class ProfileFetcher
    TIMEOUT = 5 # Reduced timeout for responsiveness
    POLL_INTERVAL = 0.5

    def initialize
      @config = Rails.application.config_for(:lievik)
      @relays = @config.dig(:nostr, :relays) || ["wss://relay.nsec.app", "wss://nos.lol"]
    end

    def fetch(pubkey_hex, relay_hints: [])
      return nil if pubkey_hex.blank?

      relays = (Array(relay_hints).select(&:present?) + @relays).uniq

      relays.each do |relay_url|
        begin
          event = fetch_from_relay(relay_url, pubkey_hex)
          if event
            profile = parse_profile(event)
            return profile if profile
          end
        rescue StandardError => e
          Rails.logger.warn("Failed to fetch profile from #{relay_url}: #{e.message}")
        end
      end

      nil
    end

    # Fetch a Nostr event by its hex ID from relays
    def fetch_event(event_id_hex, relay_hints: [])
      return nil if event_id_hex.blank?

      relays = (Array(relay_hints).select(&:present?) + @relays).uniq

      relays.each do |relay_url|
        begin
          event = fetch_event_from_relay(relay_url, event_id_hex)
          if event && event["content"]
            return {
              content: event["content"],
              pubkey: event["pubkey"],
              kind: event["kind"],
              created_at: event["created_at"]
            }
          end
        rescue StandardError => e
          Rails.logger.warn("Failed to fetch event from #{relay_url}: #{e.message}")
        end
      end

      nil
    end

    private

    def fetch_from_relay(relay_url, pubkey_hex)
      query_relay(relay_url, { "kinds" => [ 0 ], "authors" => [ pubkey_hex ], "limit" => 1 }) do |event|
        event["kind"] == 0
      end
    end

    def fetch_event_from_relay(relay_url, event_id_hex)
      query_relay(relay_url, { "ids" => [ event_id_hex ], "limit" => 1 })
    end

    # One relay query returning the first matching EVENT (or nil). Everything —
    # connect, TLS handshake, upgrade, each frame read, each write — is bounded
    # by a single deadline, and TLS certificates are verified by
    # WebsocketConnection.
    def query_relay(relay_url, filter)
      deadline = Time.current + TIMEOUT
      uri = URI.parse(relay_url)
      socket = WebsocketConnection.open(uri, deadline: deadline)
      return nil unless socket

      sub_id = SecureRandom.hex(4)
      result = nil

      begin
        WebsocketConnection.send_text(socket, [ "REQ", sub_id, filter ].to_json, deadline: deadline)

        while Time.current < deadline
          ready = WebsocketConnection.readable_now?(socket) || IO.select([ socket ], nil, nil, POLL_INTERVAL)
          next unless ready

          data = read_frame(socket, deadline)
          break unless data

          begin
            parsed = JSON.parse(data)
          rescue JSON::ParserError
            next
          end
          next unless parsed.is_a?(Array)

          if parsed[0] == "EVENT" && parsed[2].is_a?(Hash)
            event = parsed[2]
            next if block_given? && !yield(event)
            result = event
            break
          elsif parsed[0] == "EOSE" || parsed[0] == "CLOSED"
            break
          end
        end
      ensure
        close_socket(socket, sub_id)
      end

      result
    end

    def read_frame(socket, deadline)
      WebsocketFrameReader.read(socket, deadline: deadline)
    rescue WebsocketFrameReader::FrameError
      nil
    end

    def close_socket(socket, sub_id)
      WebsocketConnection.send_text(socket, [ "CLOSE", sub_id ].to_json, deadline: 1.second.from_now) rescue nil
      socket.close rescue nil
    end

    def parse_profile(event)
      return nil unless event && event["content"]

      profile_data = JSON.parse(event["content"])

      {
        display_name: profile_data["display_name"] || profile_data["displayName"] || profile_data["name"],
        username: profile_data["name"] || profile_data["username"],
        about: profile_data["about"],
        picture: profile_data["picture"]
      }
    rescue JSON::ParserError
      nil
    end
  end
end
