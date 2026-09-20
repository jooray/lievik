# frozen_string_literal: true

module Ai
  # The text a rating engine sees for an event. Shared by the chat engine
  # (Ai::RatingService) and the decision engine (Ai::DecisionRatingService) so
  # switching engines never changes *what* is judged, only *how*.
  module RatingContent
    module_function

    def prepare(event)
      parts = []

      if event.metadata["title"].present?
        parts << "Title: #{event.metadata['title']}"
      end

      parts << event.content.truncate(2000)

      if event.metadata["link"].present?
        parts << "Link: #{event.metadata['link']}"
      end

      # Include linked content summaries for additional context
      linked_context = prepare_linked_content(event)
      parts << linked_context if linked_context.present?

      parts.join("\n\n")
    end

    def prepare_linked_content(event)
      linked_contents = event.linked_contents.fetched.limit(3)
      return nil if linked_contents.empty?

      summaries = linked_contents.filter_map do |lc|
        # Skip if there was a fetch error
        next if lc.metadata&.dig("fetch_error").present?

        # Skip if content is too short to be meaningful
        next if lc.content.to_s.length < 100

        summary = lc.metadata&.dig("summary")
        title = lc.title

        # Only include if we have meaningful title or summary
        next if title.blank? && summary.blank?

        if summary.present?
          "- #{title}: #{summary}"
        else
          "- #{title}"
        end
      end

      return nil if summaries.empty?

      "Linked content:\n#{summaries.join("\n")}"
    end
  end
end
