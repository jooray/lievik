# frozen_string_literal: true

module Users
  # The dashboard counters (web dashboard, app dashboard and /me). Manual
  # sources are left out to match the sources page.
  module Stats
    def self.for(user)
      events = user.events
      {
        sources: user.sources.where.not(source_type: :manual).count,
        channels: user.channels.count,
        events: events.count,
        embedded: events.where.not(embedding: nil).count
      }
    end
  end
end
