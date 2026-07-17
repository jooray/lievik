# frozen_string_literal: true

class EventCardComponent < ViewComponent::Base
  def initialize(channel_event:)
    @channel_event = channel_event
    @event = channel_event.event
    @source = @event.source
  end

  private

  attr_reader :channel_event, :event, :source

  def relevance_color
    case channel_event.relevance_score
    when 80..100 then "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200"
    when 50..79 then "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200"
    else "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200"
    end
  end

  def event_type_badge
    case event.event_type
    when "original" then { text: "Original", class: "bg-blue-100 text-blue-800 dark:bg-blue-900 dark:text-blue-200" }
    when "reply" then { text: "Reply", class: "bg-gray-100 text-gray-600 dark:bg-gray-700 dark:text-gray-400" }
    when "repost" then { text: "Repost", class: "bg-purple-100 text-purple-800 dark:bg-purple-900 dark:text-purple-200" }
    end
  end

  def nostr_link
    nevent = event.metadata["nevent"] rescue nil
    return nil if nevent.blank?
    "https://njump.me/#{nevent}"
  end
end
