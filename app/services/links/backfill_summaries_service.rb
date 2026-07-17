# frozen_string_literal: true

module Links
  class BackfillSummariesService
    def initialize(scope: LinkedContent.all, batch_size: 25)
      @scope = scope
      @batch_size = batch_size
    end

    def call
      {
        enqueued_fetch_jobs: enqueue_unfetched_links,
        summarized_existing_links: summarize_fetched_links
      }
    end

    private

    attr_reader :scope, :batch_size

    def enqueue_unfetched_links
      ids = scope.unfetched.limit(batch_size).pluck(:id)
      return 0 if ids.empty?

      FetchLinksJob.perform_later(ids)
      ids.size
    end

    def summarize_fetched_links
      count = 0

      fetched_without_summary.each do |linked_content|
        before = linked_content.metadata&.dig("summary")
        next if before.present?

        summary = Links::SummarizationService.new(linked_content).summarize
        count += 1 if summary.present?
      end

      count
    end

    def fetched_without_summary
      scope.fetched.find_each(batch_size: batch_size).select do |linked_content|
        linked_content.metadata&.dig("summary").blank?
      end
    end
  end
end
