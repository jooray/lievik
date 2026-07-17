# frozen_string_literal: true

class FetchLinksJob < ApplicationJob
  queue_as :default

  def perform(linked_content_ids = nil)
    linked_contents = if linked_content_ids.present?
      LinkedContent.where(id: linked_content_ids)
    else
      LinkedContent.unfetched.limit(50)
    end

    return if linked_contents.empty?

    linked_contents.find_each do |linked_content|
      process_link(linked_content)
    end
  end

  private

  def process_link(linked_content)
    # Fetch content
    fetcher = Links::FetcherService.new(linked_content)
    result = fetcher.fetch

    return unless result

    # Summarize content
    summarizer = Links::SummarizationService.new(linked_content)
    summarizer.summarize

    Rails.logger.info("Processed link: #{linked_content.url} - #{linked_content.title}")
  rescue StandardError => e
    Rails.logger.error("Failed to process link #{linked_content.url}: #{e.message}")
  end
end
