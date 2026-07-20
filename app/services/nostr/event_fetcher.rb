# frozen_string_literal: true

require "json"
require "securerandom"

module Nostr
  class EventFetcher
    TIMEOUT = 10
    POLL_INTERVAL = 0.5

    def initialize
      @config = Rails.application.config_for(:lievik)
      @relays = @config.dig(:nostr, :relays) || ["wss://relay.nsec.app"]
    end

    # Nostr event kinds
    KIND_SHORT_TEXT = 1
    KIND_REPOST = 6
    KIND_LONG_FORM = 30023

    # Fetch events for a pubkey within a time range
    # Options:
    #   - kinds: Array of event kinds (default: [1, 30023] for text notes and long-form)
    #   - since: Time or timestamp to fetch events after
    #   - until_time: Time or timestamp to fetch events before
    #   - limit: Max events to fetch per relay
    #   - include_replies: Include reply events (have 'e' tags)
    #   - include_reposts: Include kind 6 reposts
    #   - include_long_form: Include kind 30023 long-form articles (default: true)
    def fetch(pubkey_hex, options = {})
      kinds = options[:kinds] || [KIND_SHORT_TEXT]
      kinds << KIND_LONG_FORM if options.fetch(:include_long_form, true) && !kinds.include?(KIND_LONG_FORM)
      kinds << KIND_REPOST if options[:include_reposts] && !kinds.include?(KIND_REPOST)

      since_ts = options[:since].is_a?(Time) ? options[:since].to_i : options[:since]
      until_ts = options[:until_time].is_a?(Time) ? options[:until_time].to_i : options[:until_time]
      limit = options[:limit] || 100

      filter = {
        "authors" => [pubkey_hex],
        "kinds" => kinds.uniq,
        "limit" => limit
      }
      filter["since"] = since_ts if since_ts
      filter["until"] = until_ts if until_ts

      all_events = []

      @relays.each do |relay_url|
        begin
          events = fetch_from_relay(relay_url, filter)
          # Tag each event with the relay it was fetched from
          events.each do |event|
            event["_seen_on_relays"] ||= []
            event["_seen_on_relays"] << relay_url unless event["_seen_on_relays"].include?(relay_url)
          end
          all_events.concat(events)
          Rails.logger.info("Fetched #{events.size} events from #{relay_url} for #{pubkey_hex[0..7]}...")
        rescue StandardError => e
          Rails.logger.warn("Failed to fetch from #{relay_url}: #{e.message}")
        end
      end

      # Dedupe by event ID and filter replies if needed
      # When deduping, merge relay lists
      events_by_id = {}
      all_events.each do |event|
        if events_by_id[event["id"]]
          # Merge relay lists
          existing_relays = events_by_id[event["id"]]["_seen_on_relays"] || []
          new_relays = event["_seen_on_relays"] || []
          events_by_id[event["id"]]["_seen_on_relays"] = (existing_relays + new_relays).uniq
          next
        end

        # Skip replies if not included
        unless options[:include_replies]
          next if event["tags"]&.any? { |t| t[0] == "e" }
        end

        events_by_id[event["id"]] = event
      end

      # created_at is relay-supplied and may be missing or non-numeric; to_i keeps
      # the sort from raising on a single malformed event.
      events_by_id.values.sort_by { |e| -e["created_at"].to_i }
    end

    private

    # One relay query, entirely bounded by a single deadline: connect, TLS
    # handshake, upgrade, every frame read and every write. TLS certificates are
    # verified by WebsocketConnection.
    def fetch_from_relay(relay_url, filter)
      deadline = Time.current + TIMEOUT
      uri = URI.parse(relay_url)
      socket = WebsocketConnection.open(uri, deadline: deadline)
      return [] unless socket

      sub_id = SecureRandom.hex(4)
      events = []

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

          case parsed[0]
          when "EVENT"
            # A relay can send anything in the payload slot. Anything that is not
            # a Hash with an id would blow up in the caller's tagging/dedupe
            # loops and take every valid event from this relay down with it.
            payload = parsed[2]
            next unless payload.is_a?(Hash) && payload["id"].is_a?(String)

            events << payload
          when "EOSE", "CLOSED"
            break
          when "NOTICE"
            Rails.logger.debug("Relay notice: #{parsed[1]}")
          end
        end
      ensure
        close_socket(socket, sub_id)
      end

      events
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
  end
end
