# frozen_string_literal: true

module Api
  module V1
    # Event (docs/API_V1.md "Representations"). Preload `:source` and
    # `channel_events: :channel` for lists.
    module EventSerializer
      IMAGE_EXTENSIONS = %w[jpg jpeg png gif webp avif svg heic].freeze
      URL_PATTERN = %r{https?://[^\s<>"'\]\)]+}i

      def self.many(events, context)
        events = events.to_a
        context.preload_authors(events)
        events.map { |event| one(event, context) }
      end

      def self.one(event, context)
        {
          id: event.id,
          source_id: event.source_id,
          source_name: event.source&.display_label,
          source_type: event.source&.source_type,
          external_id: event.external_id,
          event_type: event.event_type,
          kind: kind(event),
          content: event.content,
          title: title(event),
          published_at: Context.iso(event.published_at),
          updated_at: Context.iso(event.updated_at),
          author: context.author_for(event),
          source_url: context.safe_url(event.source_link(context.user)),
          nostr_uri: nostr_uri(event),
          images: images(event, context),
          references: references(event.content, context),
          top_channels: event.top_channel_events.map do |ce|
            { channel_id: ce.channel_id, channel_name: ce.channel&.name, relevance_score: ce.relevance_score, used: ce.used }
          end
        }
      end

      # NIP-21 link (nevent, or naddr for long-form) for the phone's own nostr apps.
      def self.nostr_uri(event)
        return nil unless event.source&.nostr?

        identifier = event.source_identifier
        identifier.present? ? "nostr:#{identifier}" : nil
      end

      def self.kind(event)
        return nil unless event.source&.nostr?

        value = event.raw_data.is_a?(Hash) ? event.raw_data["kind"] : nil
        value.is_a?(Integer) ? value : nil
      end

      def self.title(event)
        if event.source&.rss?
          event.metadata.is_a?(Hash) ? (event.metadata["title"] || event.metadata[:title]).presence : nil
        elsif event.long_form?
          tag_value(event, "title").presence
        end
      end

      # Image URLs from the content (by extension), NIP-92 imeta tags and a
      # long-form header image, http(s) only, in order, without duplicates.
      def self.images(event, context)
        urls = event.content.to_s.scan(URL_PATTERN).select { |url| image_url?(url) }

        tags(event).each do |tag|
          case tag.first
          when "imeta"
            fields = tag.drop(1).filter_map { |part| part.to_s.split(" ", 2) if part.to_s.include?(" ") }.to_h
            url = fields["url"]
            urls << url if url && (fields["m"].to_s.start_with?("image/") || image_url?(url))
          when "image"
            urls << tag[1] if tag[1].is_a?(String)
          end
        end

        urls.filter_map { |url| context.safe_url(url) }.uniq
      end

      def self.image_url?(url)
        path = URI.parse(url).path.to_s
        IMAGE_EXTENSIONS.include?(File.extname(path).delete_prefix(".").downcase)
      rescue URI::InvalidURIError
        false
      end

      # The `nostr:` references in the content, resolved like the web view does
      # (Nostr::ReferenceResolver). `uri` is the exact text to replace.
      def self.references(content, context)
        return [] if content.blank?

        content.to_enum(:scan, Nostr::ReferenceResolver::PATTERN).map { Regexp.last_match }.uniq { |m| m[0] }.filter_map do |match|
          ref = context.resolver.resolve(match[1])
          reference_json(match[0], match[1], ref) if ref
        end
      end

      def self.reference_json(uri, identifier, ref)
        case ref[:type]
        when :profile
          label = ref[:display_name].present? ? "@#{ref[:display_name]}" : "@#{ref[:npub]&.truncate(20)}"
          { uri: uri, type: "profile", label: label, url: ref[:url], npub: ref[:npub] }
        when :event
          if ref[:resolved]
            label = ref[:author_name].presence || I18n.t("app.nostr.unknown_author")
            { uri: uri, type: "event", label: label, preview: ref[:content], url: ref[:url] }
          else
            { uri: uri, type: "event", label: I18n.t("app.nostr.referenced_note"), preview: nil, url: ref[:url] }
          end
        when :article
          label = ref[:slug].present? ? ref[:slug].truncate(40) : identifier.truncate(20)
          { uri: uri, type: "article", label: label, url: ref[:url] }
        end
      end

      def self.tags(event)
        tags = event.raw_data.is_a?(Hash) ? event.raw_data["tags"] : nil
        tags.is_a?(Array) ? tags.select { |t| t.is_a?(Array) && t.first.is_a?(String) } : []
      end

      def self.tag_value(event, name)
        tags(event).find { |t| t.first == name }&.dig(1)
      end
    end
  end
end
