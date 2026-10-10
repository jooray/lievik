# frozen_string_literal: true

class RefreshAllSourcesJob < ApplicationJob
  queue_as :default

  def perform(user_id = nil)
    sources = if user_id
      # A raw id isn't covered by `discard_on DeserializationError`, so a user
      # deleted between enqueue and run would raise forever on retry.
      user = User.find_by(id: user_id)
      return unless user

      user.sources.where.not(source_type: :manual)
    else
      Source.where.not(source_type: :manual)
    end

    # Users without a trial or paid time are filtered here, once per user, so
    # their sources are never queued (SourceIngestionJob checks again anyway).
    allowed = Hash.new { |cache, id| cache[id] = Billing.allows?(User.find(id)) }
    sources.find_each do |source|
      SourceIngestionJob.perform_later(source.id) if allowed[source.user_id]
    end
  end
end
