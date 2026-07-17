# frozen_string_literal: true

class RefreshAllSourcesJob < ApplicationJob
  queue_as :default

  def perform(user_id = nil)
    sources = if user_id
      User.find(user_id).sources.where.not(source_type: :manual)
    else
      Source.where.not(source_type: :manual)
    end

    sources.find_each do |source|
      SourceIngestionJob.perform_later(source.id)
    end
  end
end
