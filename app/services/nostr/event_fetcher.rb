# frozen_string_literal: true

require "json"
require "socket"
require "openssl"
require "base64"
require "securerandom"

module Nostr
  class EventFetcher
    TIMEOUT = 10

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

      events_by_id.values.sort_by { |e| -e["created_at"] }
    end

    private

    def fetch_from_relay(relay_url, filter)
      uri = URI.parse(relay_url)
      socket = create_websocket(uri)
      return [] unless socket

      sub_id = SecureRandom.hex(4)
      req = ["REQ", sub_id, filter]
      socket.write(frame_text(req.to_json))

      events = []
      deadline = Time.now + TIMEOUT

      while Time.now < deadline
        ready = WebsocketConnection.readable_now?(socket) || IO.select([socket], nil, nil, 0.5)
        next unless ready

        data = read_websocket_frame(socket)
        break unless data

        begin
          parsed = JSON.parse(data)
          case parsed[0]
          when "EVENT"
            events << parsed[2] if parsed[2]
          when "EOSE"
            break
          when "NOTICE"
            Rails.logger.debug("Relay notice: #{parsed[1]}")
          end
        rescue JSON::ParserError
          next
        end
      end

      socket.write(frame_text(["CLOSE", sub_id].to_json)) rescue nil
      socket.close rescue nil

      events
    end

    def create_websocket(uri)
      host = uri.host
      port = uri.port || (uri.scheme == "wss" ? 443 : 80)

      tcp_socket = TCPSocket.new(host, port)
      tcp_socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

      socket = if uri.scheme == "wss"
        ctx = OpenSSL::SSL::SSLContext.new
        ssl_socket = OpenSSL::SSL::SSLSocket.new(tcp_socket, ctx)
        ssl_socket.hostname = host
        ssl_socket.connect
        ssl_socket
      else
        tcp_socket
      end

      key = Base64.strict_encode64(SecureRandom.random_bytes(16))
      path = uri.path.empty? ? "/" : uri.path
      request = ["GET #{path} HTTP/1.1", "Host: #{host}", "Upgrade: websocket", "Connection: Upgrade", "Sec-WebSocket-Key: #{key}", "Sec-WebSocket-Version: 13", "", ""].join("\r\n")
      socket.write(request)

      response = ""
      while (line = socket.gets)
        response += line
        break if line == "\r\n"
      end

      return nil unless response.include?("101")
      socket
    rescue StandardError => e
      Rails.logger.warn("WebSocket connection failed: #{e.message}")
      nil
    end

    def frame_text(data)
      bytes = data.bytes
      frame = [0x81]
      if bytes.length < 126
        frame << (0x80 | bytes.length)
      elsif bytes.length < 65536
        frame << (0x80 | 126) << (bytes.length >> 8) << (bytes.length & 0xFF)
      else
        frame << (0x80 | 127)
        8.times { |i| frame << ((bytes.length >> (56 - i * 8)) & 0xFF) }
      end
      mask = 4.times.map { rand(256) }
      frame.concat(mask)
      bytes.each_with_index { |b, i| frame << (b ^ mask[i % 4]) }
      frame.pack("C*")
    end

    def read_websocket_frame(socket)
      first_byte = socket.read(1)&.unpack1("C")
      return nil unless first_byte
      second_byte = socket.read(1)&.unpack1("C")
      return nil unless second_byte
      masked = (second_byte & 0x80) != 0
      length = second_byte & 0x7F
      if length == 126
        length = socket.read(2).unpack1("n")
      elsif length == 127
        length = socket.read(8).unpack1("Q>")
      end
      mask = masked ? socket.read(4).bytes : nil
      payload = socket.read(length)
      return nil unless payload
      if masked
        payload = payload.bytes.each_with_index.map { |b, i| b ^ mask[i % 4] }.pack("C*")
      end
      (+payload).force_encoding("UTF-8")
    rescue StandardError
      nil
    end
  end
end
