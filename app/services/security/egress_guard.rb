# frozen_string_literal: true

require "ipaddr"
require "resolv"
require "net/http"

module Security
  # Shared egress filter for every server-initiated outbound request.
  #
  # Protects against SSRF (cloud metadata endpoints, internal services reachable
  # from the app server) and against memory exhaustion from unbounded downloads.
  #
  # All outbound fetches — link fetching, RSS ingestion, relay hints parsed out
  # of untrusted Nostr content — should go through here rather than calling
  # HTTPX / URI.open / TCPSocket directly.
  class EgressGuard
    class BlockedError < StandardError; end

    HTTP_SCHEMES = %w[http https].freeze
    WEBSOCKET_SCHEMES = %w[ws wss].freeze

    MAX_REDIRECTS = 5
    MAX_RELAY_HINTS = 3
    DEFAULT_MAX_BYTES = 500_000
    DEFAULT_TIMEOUT = 15

    # Address ranges we refuse to connect to. Anything that is not globally
    # routable is a potential pivot into the internal network.
    BLOCKED_RANGES = [
      # IPv4
      "0.0.0.0/8",        # "this" network
      "10.0.0.0/8",       # private
      "100.64.0.0/10",    # carrier-grade NAT
      "127.0.0.0/8",      # loopback
      "169.254.0.0/16",   # link-local — includes cloud metadata (169.254.169.254)
      "172.16.0.0/12",    # private
      "192.0.0.0/24",     # IETF protocol assignments
      "192.0.2.0/24",     # TEST-NET-1
      "192.168.0.0/16",   # private
      "198.18.0.0/15",    # benchmarking
      "198.51.100.0/24",  # TEST-NET-2
      "203.0.113.0/24",   # TEST-NET-3
      "224.0.0.0/4",      # multicast
      "240.0.0.0/4",      # reserved / broadcast
      # IPv6
      "::/128",           # unspecified
      "::1/128",          # loopback
      "fc00::/7",         # unique local
      "fe80::/10",        # link-local
      "ff00::/8"          # multicast
    ].map { |range| IPAddr.new(range) }.freeze

    Result = Struct.new(:status, :headers, :body, :uri, :truncated) do
      def success? = status == 200
      def content_type = headers["content-type"].to_s
    end

    Redirect = Struct.new(:location)
    private_constant :Redirect

    class << self
      # Parses and validates an http(s) URL, returning [URI, [public_ip, ...]].
      # Raises BlockedError for anything we refuse to talk to.
      def validate_http_url!(url)
        uri = parse!(url, HTTP_SCHEMES)
        [ uri, resolve_public_addresses!(uri.hostname) ]
      end

      def validate_websocket_url!(url)
        uri = parse!(url, WEBSOCKET_SCHEMES)
        resolve_public_addresses!(uri.hostname)
        uri
      end

      # Non-raising predicate for filtering attacker-supplied relay hints.
      def allowed_websocket_url?(url)
        validate_websocket_url!(url)
        true
      rescue BlockedError
        false
      end

      # Relay hints come out of untrusted Nostr content (nprofile/nevent TLVs),
      # so they are filtered down to a capped list of public ws(s) endpoints
      # before the server is ever asked to connect to them.
      def filter_relay_urls(urls, max: MAX_RELAY_HINTS)
        Array(urls).filter_map { |url| url if url.present? && allowed_websocket_url?(url) }
                   .uniq
                   .first(max)
      end

      def allowed_http_url?(url)
        validate_http_url!(url)
        true
      rescue BlockedError
        false
      end

      # GET a URL with the egress filter applied to *every* redirect hop and a
      # hard byte cap enforced while streaming (not after buffering).
      #
      # Returns a Result. Raises BlockedError on a filtered/unreachable target.
      def get(url, headers: {}, timeout: DEFAULT_TIMEOUT, max_bytes: DEFAULT_MAX_BYTES)
        current = url

        MAX_REDIRECTS.times do
          uri, ips = validate_http_url!(current)
          outcome = connect_to_first_reachable(uri, ips, headers, timeout, max_bytes)
          return outcome unless outcome.is_a?(Redirect)

          # Redirect targets are untrusted too — loop back through validation.
          current = URI.join(uri, outcome.location).to_s
        end

        raise BlockedError, "Too many redirects (max #{MAX_REDIRECTS})"
      end

      private

      def parse!(url, schemes)
        uri = URI.parse(url.to_s)
        unless schemes.include?(uri.scheme)
          raise BlockedError, "Refusing scheme #{uri.scheme.inspect} (allowed: #{schemes.join(', ')})"
        end
        raise BlockedError, "URL has no host" if uri.hostname.blank?

        uri
      rescue URI::InvalidURIError, URI::InvalidComponentError => e
        raise BlockedError, "Invalid URL: #{e.message}"
      end

      # Resolves a hostname and rejects it unless *every* address it resolves to
      # is globally routable. Returns the validated addresses so the caller can
      # pin the connection to one of them and avoid a DNS-rebinding race.
      def resolve_public_addresses!(host)
        addresses = resolve(host)
        raise BlockedError, "Could not resolve host: #{host}" if addresses.empty?

        addresses.each do |address|
          if blocked_address?(address)
            raise BlockedError, "Refusing to connect to non-public address #{address} (#{host})"
          end
        end

        addresses
      end

      # A host may advertise addresses in families we have no route to (an
      # IPv6-only AAAA record on an IPv4-only host), so fall through the list.
      def connect_to_first_reachable(uri, ips, headers, timeout, max_bytes)
        last_error = nil

        ips.each do |ip|
          return perform_get(uri, ip, headers, timeout, max_bytes)
        rescue BlockedError => e
          last_error = e
        end

        raise last_error || BlockedError.new("No reachable address for #{uri.hostname}")
      end

      def resolve(host)
        return [ host ] if literal_ip?(host)

        Resolv.getaddresses(host).uniq
      rescue Resolv::ResolvError, SocketError
        []
      end

      def literal_ip?(host)
        IPAddr.new(host.to_s)
        true
      rescue IPAddr::Error
        false
      end

      def blocked_address?(address)
        ip = IPAddr.new(address.to_s)
        ip = ip.native if ip.ipv6? && ip.ipv4_mapped?

        BLOCKED_RANGES.any? { |range| range.family == ip.family && range.include?(ip) }
      rescue IPAddr::Error
        # Anything we cannot parse, we do not connect to.
        true
      end

      def perform_get(uri, ip, headers, timeout, max_bytes)
        http = Net::HTTP.new(uri.hostname, uri.port)
        # Connect to the address we just validated. The Host header and SNI still
        # use the hostname, so a second DNS answer cannot swap in an internal IP.
        http.ipaddr = ip
        http.use_ssl = uri.scheme == "https"
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.open_timeout = timeout
        http.read_timeout = timeout
        http.write_timeout = timeout

        http.start do |conn|
          request = Net::HTTP::Get.new(uri.request_uri)
          headers.each { |key, value| request[key] = value }

          conn.request(request) do |response|
            location = response["location"]
            return Redirect.new(location) if response.is_a?(Net::HTTPRedirection) && location.present?

            return read_capped(response, uri, max_bytes)
          end
        end
      rescue BlockedError
        raise
      rescue StandardError => e
        raise BlockedError, "Request failed: #{e.class}: #{e.message}"
      end

      def read_capped(response, uri, max_bytes)
        body = +""
        truncated = false

        response.read_body do |chunk|
          remaining = max_bytes - body.bytesize
          if chunk.bytesize > remaining
            body << chunk.byteslice(0, remaining) if remaining.positive?
            truncated = true
            break
          end
          body << chunk
        end

        Result.new(response.code.to_i, normalize_headers(response), body, uri, truncated)
      end

      def normalize_headers(response)
        response.each_header.to_h { |key, value| [ key.downcase, value ] }
      end
    end
  end
end
