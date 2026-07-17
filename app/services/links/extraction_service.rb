# frozen_string_literal: true

module Links
  class ExtractionService
    # Match URLs but exclude common image extensions and nostr: URIs
    URL_REGEX = %r{https?://[^\s<>\[\]"']+}i
    IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .gif .webp .svg .ico .bmp].freeze
    EXCLUDED_DOMAINS = %w[imgur.com i.imgur.com pbs.twimg.com].freeze

    def initialize(event)
      @event = event
    end

    def extract_and_save
      urls = extract_urls(@event.content)
      return [] if urls.empty?

      urls.map do |url|
        linked_content = LinkedContent.find_or_create_by!(url: url)

        EventLink.find_or_create_by!(
          event: @event,
          linked_content: linked_content,
          link_type: :url
        )

        linked_content
      end
    end

    def extract_urls(text)
      return [] if text.blank?

      urls = text.scan(URL_REGEX)

      urls.map { |url| clean_url(url) }
          .uniq
          .reject { |url| image_url?(url) }
          .reject { |url| excluded_domain?(url) }
          .first(5) # Limit to 5 links per event
    end

    private

    def clean_url(url)
      # Remove trailing punctuation that's likely not part of the URL
      url.sub(/[.,;:!?\)]+$/, "")
    end

    def image_url?(url)
      path = URI.parse(url).path.to_s.downcase
      IMAGE_EXTENSIONS.any? { |ext| path.end_with?(ext) }
    rescue URI::InvalidURIError
      false
    end

    def excluded_domain?(url)
      host = URI.parse(url).host.to_s.downcase
      EXCLUDED_DOMAINS.any? { |domain| host == domain || host.end_with?(".#{domain}") }
    rescue URI::InvalidURIError
      false
    end
  end
end
