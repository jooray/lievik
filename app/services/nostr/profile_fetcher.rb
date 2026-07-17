# frozen_string_literal: true

require "json"
require "socket"
require "openssl"
require "base64"
require "securerandom"

module Nostr
  class ProfileFetcher
    TIMEOUT = 5 # Reduced timeout for responsiveness

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
      uri = URI.parse(relay_url)
      socket = create_websocket(uri)
      return nil unless socket

      sub_id = SecureRandom.hex(4)
      req = ["REQ", sub_id, { "kinds" => [0], "authors" => [pubkey_hex], "limit" => 1 }]
      socket.write(frame_text(req.to_json))

      deadline = Time.now + TIMEOUT
      profile_event = nil

      while Time.now < deadline
        ready = WebsocketConnection.readable_now?(socket) || IO.select([socket], nil, nil, 0.5)
        next unless ready

        data = read_websocket_frame(socket)
        break unless data

        begin
          parsed = JSON.parse(data)
          if parsed[0] == "EVENT" && parsed[2] && parsed[2]["kind"] == 0
            profile_event = parsed[2]
            break
          elsif parsed[0] == "EOSE"
            break
          end
        rescue JSON::ParserError
          next
        end
      end

      # Cleanup
      socket.write(frame_text(["CLOSE", sub_id].to_json)) rescue nil
      socket.close rescue nil

      profile_event
    end

    def fetch_event_from_relay(relay_url, event_id_hex)
      uri = URI.parse(relay_url)
      socket = create_websocket(uri)
      return nil unless socket

      sub_id = SecureRandom.hex(4)
      req = ["REQ", sub_id, { "ids" => [event_id_hex], "limit" => 1 }]
      socket.write(frame_text(req.to_json))

      deadline = Time.now + TIMEOUT
      result_event = nil

      while Time.now < deadline
        ready = WebsocketConnection.readable_now?(socket) || IO.select([socket], nil, nil, 0.5)
        next unless ready

        data = read_websocket_frame(socket)
        break unless data

        begin
          parsed = JSON.parse(data)
          if parsed[0] == "EVENT" && parsed[2]
            result_event = parsed[2]
            break
          elsif parsed[0] == "EOSE"
            break
          end
        rescue JSON::ParserError
          next
        end
      end

      socket.write(frame_text(["CLOSE", sub_id].to_json)) rescue nil
      socket.close rescue nil

      result_event
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

    # Minimal WebSocket frame implementation (copied from Nip46Client logic)
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
