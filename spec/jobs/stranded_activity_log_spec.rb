# frozen_string_literal: true

require "rails_helper"

# Regression cover for the "142 phantom progress cards" incident.
#
# A crash-looping deploy interrupted SourceIngestionJob mid-run ~70 times. Each
# attempt created a "running" ActivityLog and then unwound *without* raising a
# StandardError (the worker thread is interrupted on shutdown, not handed an
# exception), so neither the success nor the `rescue` branch ever fired and every
# log was stranded as a permanent progress card on the dashboard.
#
# The recurring sweep that would have reaped them (`ActivityLog.mark_stale_as_failed!`)
# is a `command:` task, so it lands on the `solid_queue_recurring` queue — which
# no worker in config/queue.yml was listening on. Both halves are covered here.
RSpec.describe "Stranded activity logs" do
  let!(:user) { User.create!(npub: "npub1sweeper", pubkey_hex: "a" * 64, display_name: "Sweeper") }
  let!(:source) do
    user.sources.create!(source_type: :nostr, identifier: "b" * 64, name: "Src", distance: 5)
  end

  describe "SourceIngestionJob interrupted mid-run" do
    it "marks the log failed instead of leaving it running" do
      # Interrupt with something that is NOT a StandardError, exactly as a worker
      # shutdown does — the `rescue StandardError` branch must not be what saves us.
      allow(Ingestion::NostrIngestionService).to receive(:new).and_raise(Interrupt)

      expect { SourceIngestionJob.perform_now(source.id) }.to raise_error(Interrupt)

      log = user.activity_logs.last
      expect(log.status).to eq("failed")
      expect(log.message).to match(/Interrupted/)
      expect(user.activity_logs.active).to be_empty
    end
  end

  describe "the on-read sweep" do
    it "reaps a log stranded by an older interrupted run" do
      stranded = ActivityLog.start_activity(
        user: user, activity_type: "ingestion", message: "Ingesting from Src"
      )
      stranded.update_columns(updated_at: (ActivityLog::STALE_AFTER + 1.minute).ago)

      expect(user.activity_logs.active).to include(stranded)
      user.activity_logs.mark_stale_as_failed!

      expect(stranded.reload.status).to eq("failed")
      expect(user.activity_logs.active).to be_empty
    end

    it "leaves a genuinely in-flight log alone" do
      fresh = ActivityLog.start_activity(
        user: user, activity_type: "ingestion", message: "Ingesting from Src"
      )

      user.activity_logs.mark_stale_as_failed!

      expect(fresh.reload.status).to eq("running")
    end
  end

  describe "queue configuration" do
    it "has a worker listening on the queue SolidQueue::RecurringJob uses" do
      config = YAML.load(ERB.new(Rails.root.join("config/queue.yml").read).result, aliases: true)
      workers = config.fetch("production").fetch("workers")

      # Solid Queue does `Array(options[:queues])` — a comma-separated *string*
      # becomes one queue name containing a comma, matching nothing. Assert the
      # exact structure the worker will see, not a comma-split of it.
      workers.each { |w| expect(w.fetch("queues")).to be_an(Array) }

      listened = workers.flat_map { |w| w.fetch("queues") }
      expect(listened).to include(SolidQueue::RecurringJob.queue_name)
      expect(listened).to include("default")
    end
  end
end
