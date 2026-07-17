namespace :links do
  desc "Backfill fetched links with summaries and enqueue unfetched links for fetch+summarize"
  task backfill_summaries: :environment do
    result = Links::BackfillSummariesService.new.call

    puts "Enqueued fetch jobs for #{result[:enqueued_fetch_jobs]} unfetched links"
    puts "Summarized #{result[:summarized_existing_links]} fetched links missing summaries"
  end
end
