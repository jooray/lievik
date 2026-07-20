# frozen_string_literal: true

require "rss"

module Ingestion
  class RssIngestionService
    USER_AGENT = "Lievik/1.0 (RSS Reader)"
    TIMEOUT = 30
    MAX_FEED_BYTES = 5_000_000 # 5MB — feeds larger than this are rejected, not buffered
    # events.content is MEDIUMTEXT on MariaDB (16 MB). A single `content:encoded`
    # body is capped well below that so an insert can never fail on length.
    MAX_CONTENT_BYTES = 1_000_000

    def initialize(source, activity_log_id: nil)
      @source = source
      @user = source.user
      @activity_log_id = activity_log_id
    end

    def ingest
      return { success: false, error: "Source is not an RSS source" } unless @source.rss?

      feed_url = @source.identifier
      return { success: false, error: "Invalid feed URL" } unless valid_url?(feed_url)

      Rails.logger.info("Ingesting RSS feed: #{feed_url}")

      begin
        feed_content = fetch_feed(feed_url)
        feed = parse_feed(feed_content)

        return { success: false, error: "Could not parse feed" } unless feed

        imported_count = 0
        skipped_count = 0
        imported_event_ids = []
        new_linked_content_ids = []

        items = extract_items(feed)

        items.each do |item|
          begin
            result = import_item(item)

            if result
              imported_count += 1
              imported_event_ids << result.id
              # Extract links from the new event
              linked_contents = Links::ExtractionService.new(result).extract_and_save
              new_linked_content_ids.concat(linked_contents.select { |lc| lc.fetched_at.nil? }.map(&:id))
            else
              skipped_count += 1
            end
          rescue ActiveRecord::RecordNotUnique
            # Concurrent ingestion of the same source imported this item first.
            skipped_count += 1
          rescue StandardError => e
            # One malformed item must never abort the rest of the feed.
            Rails.logger.warn("Skipping bad RSS item: #{e.class} - #{e.message}")
            skipped_count += 1
          end
        end

        # Queue link fetching job if there are new links
        if new_linked_content_ids.any?
          FetchLinksJob.perform_later(new_linked_content_ids.uniq)
        end

        # Update source name from feed if blank
        if @source.name.blank? && feed.respond_to?(:channel) && feed.channel.respond_to?(:title)
          @source.update(name: feed.channel.title)
        elsif @source.name.blank? && feed.respond_to?(:title)
          @source.update(name: feed.title.content) rescue nil
        end

        Rails.logger.info("RSS ingestion complete: #{imported_count} imported, #{skipped_count} skipped")

        { success: true, imported: imported_count, skipped: skipped_count, event_ids: imported_event_ids }
      rescue StandardError => e
        Rails.logger.error("RSS ingestion failed: #{e.message}")
        { success: false, error: e.message }
      end
    end

    private

    def valid_url?(url)
      Security::EgressGuard.allowed_http_url?(url)
    end

    def fetch_feed(url)
      # EgressGuard re-applies the SSRF filter on every redirect hop and caps the
      # body while streaming — URI.open did neither.
      response = Security::EgressGuard.get(
        url,
        headers: { "user-agent" => USER_AGENT },
        timeout: TIMEOUT,
        max_bytes: MAX_FEED_BYTES
      )
      raise "Feed returned HTTP #{response.status}" unless response.success?
      raise "Feed larger than #{MAX_FEED_BYTES} bytes" if response.truncated

      response.body
    end

    def parse_feed(content)
      RSS::Parser.parse(content, false)
    rescue RSS::Error => e
      Rails.logger.warn("RSS parse error: #{e.message}")
      nil
    end

    def extract_items(feed)
      if feed.respond_to?(:items)
        feed.items
      elsif feed.respond_to?(:entries)
        feed.entries
      else
        []
      end
    end

    def import_item(item)
      external_id = extract_id(item)
      return nil if external_id.blank?
      return nil if @source.events.exists?(external_id: external_id)

      content = extract_content(item)
      return nil if content.blank?

      published_at = extract_date(item) || Time.current

      event = @source.events.create(
        external_id: external_id,
        content: truncate_content(content),
        event_type: :original,
        published_at: published_at,
        raw_data: item_to_hash(item),
        metadata: {
          title: extract_title(item),
          link: extract_link(item)
        }
      )

      event.persisted? ? event : nil
    end

    def truncate_content(content)
      return content unless content.is_a?(String)
      return content if content.bytesize <= MAX_CONTENT_BYTES

      Rails.logger.warn("Truncating oversized RSS item content (#{content.bytesize} bytes)")
      content.byteslice(0, MAX_CONTENT_BYTES).scrub("")
    end

    def extract_id(item)
      if item.respond_to?(:guid) && item.guid
        item.guid.content rescue item.guid.to_s
      elsif item.respond_to?(:id) && item.id
        item.id.content rescue item.id.to_s
      elsif item.respond_to?(:link)
        extract_link(item)
      end
    end

    def extract_title(item)
      if item.respond_to?(:title)
        item.title.respond_to?(:content) ? item.title.content : item.title.to_s
      end
    end

    def extract_content(item)
      content = nil

      # Try content:encoded first (full content)
      if item.respond_to?(:content_encoded) && item.content_encoded.present?
        content = item.content_encoded
      # Try content element (Atom)
      elsif item.respond_to?(:content) && item.content.present?
        content = item.content.respond_to?(:content) ? item.content.content : item.content.to_s
      # Fall back to description
      elsif item.respond_to?(:description) && item.description.present?
        content = item.description.respond_to?(:content) ? item.description.content : item.description.to_s
      # Try summary (Atom)
      elsif item.respond_to?(:summary) && item.summary.present?
        content = item.summary.respond_to?(:content) ? item.summary.content : item.summary.to_s
      end

      # Strip HTML tags for plain text content
      strip_html(content) if content
    end

    def extract_link(item)
      return nil unless item.respond_to?(:link)

      link = item.link
      raw = if link.respond_to?(:href)
        link.href
      elsif link.is_a?(String)
        link
      else
        link.to_s
      end

      safe_link(raw)
    end

    # Feed-supplied links are rendered into href attributes ("View Original"),
    # so anything but http(s) — notably javascript: — is dropped at ingestion.
    def safe_link(url)
      return nil if url.blank?

      uri = URI.parse(url.to_s.strip)
      return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      return nil if uri.host.blank?

      uri.to_s
    rescue URI::InvalidURIError
      nil
    end

    def extract_date(item)
      date = nil

      if item.respond_to?(:pubDate) && item.pubDate
        date = item.pubDate
      elsif item.respond_to?(:published) && item.published
        date = item.published.respond_to?(:content) ? item.published.content : item.published
      elsif item.respond_to?(:updated) && item.updated
        date = item.updated.respond_to?(:content) ? item.updated.content : item.updated
      elsif item.respond_to?(:dc_date) && item.dc_date
        date = item.dc_date
      end

      date.is_a?(Time) ? date : Time.parse(date.to_s) rescue nil
    end

    def strip_html(html)
      return nil if html.blank?

      doc = Nokogiri::HTML.fragment(html)
      doc.css("script, style, nav, header, footer").remove
      text = doc.text
      text.gsub(/\s+/, " ").strip
    end

    def item_to_hash(item)
      {
        title: extract_title(item),
        link: extract_link(item),
        guid: extract_id(item),
        pub_date: extract_date(item)&.iso8601
      }
    end
  end
end
