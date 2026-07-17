# frozen_string_literal: true

require "rss"
require "open-uri"

module Ingestion
  class RssIngestionService
    USER_AGENT = "Lievik/1.0 (RSS Reader)"
    TIMEOUT = 30

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
      uri = URI.parse(url)
      uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    rescue URI::InvalidURIError
      false
    end

    def fetch_feed(url)
      URI.open(url,
        "User-Agent" => USER_AGENT,
        read_timeout: TIMEOUT,
        open_timeout: TIMEOUT
      ).read
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
        content: content,
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
      if item.respond_to?(:link)
        link = item.link
        if link.respond_to?(:href)
          link.href
        elsif link.is_a?(String)
          link
        else
          link.to_s
        end
      end
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
