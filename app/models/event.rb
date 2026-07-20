# frozen_string_literal: true

class Event < ApplicationRecord
  attribute :metadata, :json, default: -> { {} }
  attribute :raw_data, :json, default: -> { {} }

  belongs_to :source
  has_many :channel_events, dependent: :destroy
  has_many :channels, through: :channel_events
  has_many :event_links, dependent: :destroy
  has_many :linked_contents, through: :event_links
  has_many :channel_content_events, dependent: :destroy
  has_many :channel_contents, through: :channel_content_events

  enum :event_type, { original: 0, reply: 1, repost: 2, long_form: 3 }

  validates :external_id, uniqueness: { scope: :source_id }
  # An empty event is worthless and still costs paid AI rating calls on every
  # channel, so never let one in. Both ingestion services already skip blank
  # content upstream, so this only guards the manual-entry path.
  validates :content, presence: true

  scope :recent, -> { order(published_at: :desc) }
  scope :originals_only, -> { where(event_type: :original) }

  # Get the source identifier for this event
  # For Nostr long-form: naddr bech32 string (parameterized replaceable)
  # For Nostr regular: nevent bech32 string
  # For RSS: the original URL
  def source_identifier
    case source.source_type
    when "nostr"
      # Long-form content uses naddr (parameterized replaceable)
      if long_form?
        naddr_id || nevent_id
      else
        nevent_id
      end
    when "rss"
      # RSS events store the link URL in metadata or external_id
      metadata&.dig("link") || external_id
    else
      external_id
    end
  end

  # Generate nevent bech32 identifier for Nostr events
  # Includes relay hints if available
  def nevent_id
    return nil unless source.nostr?

    # external_id is the hex event ID for Nostr events
    hex_event_id = external_id
    return nil unless hex_event_id.present? && hex_event_id.match?(/\A[0-9a-f]{64}\z/i)

    # Get author pubkey from the event's raw_data (stored during ingestion)
    author_pubkey = raw_data&.dig("pubkey")

    # Get kind from raw_data if available
    kind = raw_data&.dig("kind")

    # Get relay hints from raw_data (stored during ingestion)
    # Use first relay as the hint
    relays = raw_data&.dig("_seen_on_relays") || []
    relay = relays.first

    Nostr::KeyConverter.hex_to_nevent(hex_event_id, relay: relay, author_pubkey: author_pubkey, kind: kind)
  end

  # Get the note1 identifier (simple, without relay hints)
  def note_id
    return nil unless source.nostr?

    hex_event_id = external_id
    return nil unless hex_event_id.present? && hex_event_id.match?(/\A[0-9a-f]{64}\z/i)

    Nostr::KeyConverter.hex_to_note(hex_event_id)
  end

  # Generate naddr bech32 identifier for long-form (replaceable) Nostr events
  # naddr contains: kind + pubkey + d-tag + optional relay hints
  def naddr_id
    return nil unless source.nostr? && long_form?

    d_tag = metadata&.dig("d_tag")
    return nil if d_tag.blank?

    author_pubkey = raw_data&.dig("pubkey")
    return nil if author_pubkey.blank?

    kind = raw_data&.dig("kind") || 30023

    # Get relay hints
    relays = raw_data&.dig("_seen_on_relays") || []
    relay = relays.first

    Nostr::KeyConverter.hex_to_naddr(
      kind: kind,
      pubkey: author_pubkey,
      identifier: d_tag,
      relay: relay
    )
  end

  # Returns content with nostr: references resolved to plain text
  # Used for embedding/indexing — no HTML, just readable text
  def content_for_embedding
    return content if content.blank?

    content.gsub(NostrContentHelper::NOSTR_URI_PATTERN) do |match|
      identifier = match.sub(/\Anostr:/i, "")
      resolve_nostr_reference_text(identifier)
    end
  end

  # Generate a full URL link to this event using the user's template
  def source_link(user = nil)
    identifier = source_identifier
    return nil if identifier.blank?

    case source.source_type
    when "nostr"
      if long_form? && identifier.start_with?("naddr")
        # Use naddr template for long-form content
        template = user&.naddr_link_template || User::DEFAULT_NADDR_LINK_TEMPLATE
        template.gsub("{naddr}", identifier)
      else
        # Use event template for regular events
        template = user&.event_link_template || User::DEFAULT_EVENT_LINK_TEMPLATE
        template.gsub("{eventid}", identifier)
      end
    when "rss"
      # RSS identifier is already a URL
      identifier
    else
      nil
    end
  end

  private

  def resolve_nostr_reference_text(identifier)
    parsed = Nostr::KeyConverter.parse_nostr_identifier(identifier)
    return "nostr:#{identifier}" unless parsed

    case parsed[:type]
    when :nprofile, :npub
      pubkey_hex = parsed[:pubkey]
      return "nostr:#{identifier}" unless pubkey_hex
      npub = Nostr::KeyConverter.hex_to_npub(pubkey_hex)
      source = Source.find_by(identifier: npub, source_type: :nostr)
      known_user = User.find_by(pubkey_hex: pubkey_hex) unless source
      display_name = source&.name || known_user&.display_name || known_user&.username
      unless display_name.present?
        profile = Rails.cache.read("nostr_profile:#{pubkey_hex}") rescue nil
        display_name = profile&.dig(:display_name) || profile&.dig(:username)
      end
      display_name.present? ? "@#{display_name}" : "@#{npub&.truncate(20)}"
    when :nevent, :note
      event = Event.find_by(external_id: parsed[:event_id]) if parsed[:event_id]
      unless event&.content.present?
        fetched = Rails.cache.read("nostr_event:#{parsed[:event_id]}") rescue nil
        return "[referenced note: #{fetched[:content].truncate(80)}]" if fetched&.dig(:content).present?
      end
      event&.content.present? ? "[referenced note: #{event.content.truncate(80)}]" : "[referenced note]"
    when :naddr
      label = parsed[:identifier].present? ? parsed[:identifier].truncate(60) : "article"
      "[referenced article: #{label}]"
    else
      "nostr:#{identifier}"
    end
  end
end
