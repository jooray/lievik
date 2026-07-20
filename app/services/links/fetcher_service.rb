# frozen_string_literal: true

module Links
  class FetcherService
    USER_AGENT = "Lievik/1.0 (Content Fetcher; +https://github.com/anthropics/lievik)"
    TIMEOUT = 15
    MAX_CONTENT_LENGTH = 500_000 # 500KB max

    # Patterns that indicate blocked/error pages
    BLOCKED_PATTERNS = [
      /access\s*denied/i,
      /permission\s*denied/i,
      /403\s*forbidden/i,
      /401\s*unauthorized/i,
      /blocked/i,
      /captcha/i,
      /please\s+enable\s+(javascript|cookies)/i,
      /browser\s+check/i,
      /cloudflare/i,
      /just\s+a\s+moment/i,
      /checking\s+(your\s+)?browser/i,
      /ray\s*id/i,
      /ddos\s*protection/i,
      /bot\s*detection/i,
      /are\s+you\s+a\s+human/i,
      /verify\s+you\s+are\s+human/i,
      /too\s+many\s+requests/i,
      /rate\s+limit/i
    ].freeze

    MIN_CONTENT_LENGTH = 100 # Minimum meaningful content length

    def initialize(linked_content)
      @linked_content = linked_content
    end

    def fetch
      return if @linked_content.fetched_at.present?

      response = fetch_url(@linked_content.url)
      return mark_failed("Failed to fetch") unless response

      content_type = response.headers["content-type"].to_s
      unless content_type.include?("text/html") || content_type.include?("text/plain")
        return mark_failed("Not HTML content: #{content_type}")
      end

      html = response.body.to_s
      extracted = extract_content(html)

      # Check if content looks like a blocked/error page
      if blocked_content?(extracted[:title], extracted[:content])
        return mark_failed("Blocked or error page detected")
      end

      # Check minimum content length
      if extracted[:content].to_s.length < MIN_CONTENT_LENGTH
        return mark_failed("Content too short (likely not meaningful)")
      end

      @linked_content.update!(
        title: extracted[:title],
        content: extracted[:content],
        metadata: {
          description: extracted[:description],
          fetched_url: response.uri.to_s,
          content_type: content_type
        },
        fetched_at: Time.current
      )

      @linked_content
    rescue StandardError => e
      mark_failed(e.message)
    end

    private

    def fetch_url(url)
      # EgressGuard applies the SSRF filter to every redirect hop and enforces
      # MAX_CONTENT_LENGTH while streaming, so a huge body can't be buffered.
      response = Security::EgressGuard.get(
        url,
        headers: { "user-agent" => USER_AGENT },
        timeout: TIMEOUT,
        max_bytes: MAX_CONTENT_LENGTH
      )
      return nil unless response.success?
      return nil if response.truncated

      response
    rescue Security::EgressGuard::BlockedError => e
      Rails.logger.info("Link fetch blocked: #{e.message}")
      nil
    rescue StandardError
      nil
    end

    def extract_content(html)
      doc = Nokogiri::HTML(html)

      # Remove script, style, nav, header, footer, aside elements
      doc.css("script, style, nav, header, footer, aside, noscript, iframe").remove

      title = extract_title(doc)
      description = extract_description(doc)
      content = extract_main_content(doc)

      {
        title: title&.truncate(500),
        description: description&.truncate(1000),
        content: content&.truncate(10_000)
      }
    end

    def extract_title(doc)
      # Try og:title first, then regular title
      og_title = doc.at('meta[property="og:title"]')&.attr("content")
      return og_title if og_title.present?

      doc.at("title")&.text&.strip
    end

    def extract_description(doc)
      # Try og:description, then meta description
      og_desc = doc.at('meta[property="og:description"]')&.attr("content")
      return og_desc if og_desc.present?

      doc.at('meta[name="description"]')&.attr("content")
    end

    def extract_main_content(doc)
      # Try to find main content area
      main = doc.at("article") || doc.at("main") || doc.at('[role="main"]') || doc.at(".post-content") || doc.at(".entry-content")

      if main
        text = main.text
      else
        # Fall back to body
        text = doc.at("body")&.text || ""
      end

      # Clean up whitespace
      text.gsub(/\s+/, " ").strip
    end

    def blocked_content?(title, content)
      text_to_check = "#{title} #{content}".to_s

      BLOCKED_PATTERNS.any? { |pattern| text_to_check.match?(pattern) }
    end

    def mark_failed(reason)
      @linked_content.update!(
        metadata: (@linked_content.metadata || {}).merge(
          "fetch_error" => reason,
          "fetch_attempted_at" => Time.current.iso8601
        )
      )
      nil
    end
  end
end
