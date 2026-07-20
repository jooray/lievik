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

    sources.find_each do |source|
      SourceIngestionJob.perform_later(source.id)
    end
  end
end
