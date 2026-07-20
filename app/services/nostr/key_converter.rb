# frozen_string_literal: true

require "bech32"

module Nostr
  class KeyConverter
    BECH32_CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"

    # TLV type constants for NIP-19 shareable identifiers
    TLV_SPECIAL = 0   # event id or pubkey
    TLV_RELAY = 1     # relay URL
    TLV_AUTHOR = 2    # author pubkey
    TLV_KIND = 3      # event kind

    class << self
      def hex_to_npub(hex_pubkey)
        return nil if hex_pubkey.blank?

        bytes = [hex_pubkey].pack("H*").bytes
        ::Bech32.encode("npub", convert_bits(bytes, 8, 5), ::Bech32::Encoding::BECH32)
      end

      # Convert hex event ID to note1 bech32 format (simple, no hints)
      def hex_to_note(hex_event_id)
        return nil if hex_event_id.blank?

        bytes = [hex_event_id].pack("H*").bytes
        ::Bech32.encode("note", convert_bits(bytes, 8, 5), ::Bech32::Encoding::BECH32)
      end

      # Convert hex event ID to nevent bech32 format (NIP-19 TLV encoding)
      # Optionally include relay hints and author pubkey
      def hex_to_nevent(hex_event_id, relay: nil, author_pubkey: nil, kind: nil)
        return nil if hex_event_id.blank?

        tlv_data = []

        # Type 0: Event ID (required, 32 bytes)
        event_id_bytes = [hex_event_id].pack("H*").bytes
        tlv_data << TLV_SPECIAL
        tlv_data << 32
        tlv_data.concat(event_id_bytes)

        # Type 1: Relay URL (optional, ascii)
        if relay.present?
          relay_bytes = relay.bytes
          tlv_data << TLV_RELAY
          tlv_data << relay_bytes.length
          tlv_data.concat(relay_bytes)
        end

        # Type 2: Author pubkey (optional, 32 bytes)
        if author_pubkey.present?
          author_bytes = [author_pubkey].pack("H*").bytes
          tlv_data << TLV_AUTHOR
          tlv_data << 32
          tlv_data.concat(author_bytes)
        end

        # Type 3: Kind (optional, 4 bytes big-endian)
        if kind.present?
          kind_bytes = [kind.to_i].pack("N").bytes # big-endian uint32
          tlv_data << TLV_KIND
          tlv_data << 4
          tlv_data.concat(kind_bytes)
        end

        ::Bech32.encode("nevent", convert_bits(tlv_data, 8, 5), ::Bech32::Encoding::BECH32)
      end

      # Convert to naddr bech32 format for parameterized replaceable events (NIP-19 TLV encoding)
      # Used for kind 30023 (long-form content) and other addressable events
      def hex_to_naddr(kind:, pubkey:, identifier:, relay: nil)
        return nil if kind.blank? || pubkey.blank? || identifier.blank?

        tlv_data = []

        # Type 0: d-tag identifier (required, ascii string)
        identifier_bytes = identifier.to_s.bytes
        tlv_data << TLV_SPECIAL
        tlv_data << identifier_bytes.length
        tlv_data.concat(identifier_bytes)

        # Type 1: Relay URL (optional, ascii)
        if relay.present?
          relay_bytes = relay.bytes
          tlv_data << TLV_RELAY
          tlv_data << relay_bytes.length
          tlv_data.concat(relay_bytes)
        end

        # Type 2: Author pubkey (required, 32 bytes)
        author_bytes = [pubkey].pack("H*").bytes
        tlv_data << TLV_AUTHOR
        tlv_data << 32
        tlv_data.concat(author_bytes)

        # Type 3: Kind (required, 4 bytes big-endian)
        kind_bytes = [kind.to_i].pack("N").bytes
        tlv_data << TLV_KIND
        tlv_data << 4
        tlv_data.concat(kind_bytes)

        ::Bech32.encode("naddr", convert_bits(tlv_data, 8, 5), ::Bech32::Encoding::BECH32)
      end

      # Decode nevent back to components
      def nevent_to_hex(nevent)
        return nil if nevent.blank?

        hrp, data, _spec = ::Bech32.decode(nevent, nevent.length + 10)
        return nil unless hrp == "nevent"

        bytes = convert_bits(data, 5, 8, false)
        return nil if bytes.nil?

        result = { event_id: nil, relays: [], author: nil, kind: nil }
        i = 0

        while i < bytes.length
          type = bytes[i]
          length = bytes[i + 1]
          break if length.nil? || i + 2 + length > bytes.length

          value = bytes[i + 2, length]

          case type
          when TLV_SPECIAL
            result[:event_id] = value.pack("C*").unpack1("H*")
          when TLV_RELAY
            result[:relays] << value.pack("C*")
          when TLV_AUTHOR
            result[:author] = value.pack("C*").unpack1("H*")
          when TLV_KIND
            result[:kind] = value.pack("C*").unpack1("N")
          end

          i += 2 + length
        end

        result
      end

      def npub_to_hex(npub)
        return nil if npub.blank?
        return npub if npub.match?(/\A[0-9a-f]{64}\z/i)

        hrp, data, _spec = ::Bech32.decode(npub)
        return nil unless hrp == "npub"

        # convert_bits returns nil on invalid padding, and a crafted-but-valid
        # checksum can decode to the wrong length. Never let either reach .pack.
        bytes = convert_bits(data, 5, 8, false)
        return nil unless bytes.is_a?(Array) && bytes.length == 32

        bytes.pack("C*").unpack1("H*")
      rescue StandardError
        nil
      end

      # Decode note1 to hex event ID
      def note_to_hex(note)
        return nil if note.blank?
        return note if note.match?(/\A[0-9a-f]{64}\z/i) # Already hex

        hrp, data, _spec = ::Bech32.decode(note)
        return nil unless hrp == "note"

        bytes = convert_bits(data, 5, 8, false)
        return nil unless bytes.is_a?(Array) && bytes.length == 32

        bytes.pack("C*").unpack1("H*")
      rescue StandardError
        nil
      end

      # Decode naddr1 to components (kind, pubkey, d-tag, relays)
      def naddr_to_components(naddr)
        return nil if naddr.blank?

        hrp, data, _spec = ::Bech32.decode(naddr, naddr.length + 10)
        return nil unless hrp == "naddr"

        bytes = convert_bits(data, 5, 8, false)
        return nil if bytes.nil?

        result = { identifier: nil, relays: [], pubkey: nil, kind: nil }
        i = 0

        while i < bytes.length
          type = bytes[i]
          length = bytes[i + 1]
          break if length.nil? || i + 2 + length > bytes.length

          value = bytes[i + 2, length]

          case type
          when TLV_SPECIAL # d-tag identifier
            result[:identifier] = value.pack("C*")
          when TLV_RELAY
            result[:relays] << value.pack("C*")
          when TLV_AUTHOR
            result[:pubkey] = value.pack("C*").unpack1("H*")
          when TLV_KIND
            result[:kind] = value.pack("C*").unpack1("N")
          end

          i += 2 + length
        end

        result
      rescue StandardError
        nil
      end

      # Decode nprofile back to components (pubkey + relay hints)
      def nprofile_to_components(nprofile)
        return nil if nprofile.blank?

        hrp, data, _spec = ::Bech32.decode(nprofile, nprofile.length + 10)
        return nil unless hrp == "nprofile"

        bytes = convert_bits(data, 5, 8, false)
        return nil if bytes.nil?

        result = { pubkey: nil, relays: [] }
        i = 0

        while i < bytes.length
          type = bytes[i]
          length = bytes[i + 1]
          break if length.nil? || i + 2 + length > bytes.length

          value = bytes[i + 2, length]

          case type
          when TLV_SPECIAL
            result[:pubkey] = value.pack("C*").unpack1("H*")
          when TLV_RELAY
            result[:relays] << value.pack("C*")
          end

          i += 2 + length
        end

        result
      rescue StandardError
        nil
      end

      # Parse any nostr identifier (note1, nevent1, naddr1, npub1, nprofile1, hex) and return event ID if applicable
      def parse_nostr_identifier(identifier)
        return nil if identifier.blank?

        # Remove nostr: prefix if present
        id = identifier.sub(/\Anostr:/i, "")

        if id.start_with?("note1")
          { type: :note, event_id: note_to_hex(id) }
        elsif id.start_with?("nevent1")
          data = nevent_to_hex(id)
          { type: :nevent, event_id: data&.dig(:event_id), relays: data&.dig(:relays), author: data&.dig(:author) }
        elsif id.start_with?("naddr1")
          data = naddr_to_components(id)
          { type: :naddr, identifier: data&.dig(:identifier), kind: data&.dig(:kind), pubkey: data&.dig(:pubkey) }
        elsif id.start_with?("nprofile1")
          data = nprofile_to_components(id)
          { type: :nprofile, pubkey: data&.dig(:pubkey), relays: data&.dig(:relays) }
        elsif id.start_with?("npub1")
          { type: :npub, pubkey: npub_to_hex(id) }
        elsif id.match?(/\A[0-9a-f]{64}\z/i)
          { type: :hex, event_id: id }
        else
          nil
        end
      rescue StandardError
        nil
      end

      def hex_to_nsec(hex_privkey)
        return nil if hex_privkey.blank?

        bytes = [hex_privkey].pack("H*").bytes
        ::Bech32.encode("nsec", convert_bits(bytes, 8, 5), ::Bech32::Encoding::BECH32)
      end

      def nsec_to_hex(nsec)
        return nil if nsec.blank?

        hrp, data, _spec = ::Bech32.decode(nsec)
        return nil unless hrp == "nsec"

        bytes = convert_bits(data, 5, 8, false)
        return nil unless bytes.is_a?(Array) && bytes.length == 32

        bytes.pack("C*").unpack1("H*")
      rescue StandardError
        nil
      end

      def valid_npub?(npub)
        return false if npub.blank?

        hrp, data, _spec = ::Bech32.decode(npub)
        return false unless hrp == "npub" && data.length == 52

        # A valid checksum is not enough: the 5→8 bit regrouping still has to
        # produce a well-formed 32-byte key.
        !npub_to_hex(npub).nil?
      rescue StandardError
        false
      end

      def valid_hex_pubkey?(hex)
        return false if hex.blank?

        hex.match?(/\A[0-9a-f]{64}\z/i)
      end

      private

      def convert_bits(data, from_bits, to_bits, pad = true)
        acc = 0
        bits = 0
        ret = []
        maxv = (1 << to_bits) - 1
        max_acc = (1 << (from_bits + to_bits - 1)) - 1

        data.each do |value|
          acc = ((acc << from_bits) | value) & max_acc
          bits += from_bits
          while bits >= to_bits
            bits -= to_bits
            ret << ((acc >> bits) & maxv)
          end
        end

        if pad && bits > 0
          ret << ((acc << (to_bits - bits)) & maxv)
        elsif bits >= from_bits || ((acc << (to_bits - bits)) & maxv) != 0
          return nil
        end

        ret
      end
    end
  end
end
