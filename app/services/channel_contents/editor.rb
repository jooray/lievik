# frozen_string_literal: true

module ChannelContents
  # Creating and saving drafts in the content builder. Shared by
  # ChannelContentsController and the app API.
  module Editor
    def self.parse_event_ids(raw)
      return [] if raw.blank?

      values = raw.is_a?(String) ? JSON.parse(raw) : Array.wrap(raw).reject(&:blank?)
      Array.wrap(values)
    rescue JSON::ParserError
      []
    end

    # Returns the draft, persisted or carrying its validation errors. Event ids
    # resolve through the user's own events (they are sequential integers, so an
    # unscoped lookup would attach another user's content).
    def self.create(channel, user, attributes, raw_event_ids)
      content = channel.channel_contents.build(attributes)
      content.user = user
      return content unless content.save

      event_ids = parse_event_ids(raw_event_ids)
      event_ids = event_ids.empty? ? [] : user.events.where(id: event_ids).pluck(:id)
      # All-or-nothing: a silently dropped association would give the generator
      # a different event set than the user selected.
      ChannelContentEvent.transaction do
        event_ids.each { |event_id| content.channel_content_events.create!(event_id: event_id) }
      end
      content
    end

    # Saves the current text as a version first when the text changes.
    def self.update(content, attributes)
      submitted = attributes.to_h.stringify_keys["content"]
      content.add_version(content.content) if !submitted.nil? && content.content != submitted
      content.update(attributes)
    end
  end
end
