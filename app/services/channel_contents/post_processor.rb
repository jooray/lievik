# frozen_string_literal: true

module ChannelContents
  # What generated content goes through before it is saved: markdown fences
  # around the whole answer are stripped, and nostr: URIs become web links
  # using the user's link templates.
  module PostProcessor
    def self.call(content, user)
      return content if content.blank?

      replace_nostr_uris(strip_markdown_fences(content), user)
    end

    # Strip markdown code fences from the beginning and end of AI responses
    def self.strip_markdown_fences(content)
      return content if content.blank?

      result = content.dup

      # Strip opening fence at the very beginning
      if result.start_with?("```markdown\n")
        result = result.sub(/\A```markdown\n/, "")
      elsif result.start_with?("```markdown\r\n")
        result = result.sub(/\A```markdown\r\n/, "")
      elsif result.start_with?("```\n")
        result = result.sub(/\A```\n/, "")
      elsif result.start_with?("```\r\n")
        result = result.sub(/\A```\r\n/, "")
      end

      # Strip closing fence at the very end
      if result.end_with?("\n```")
        result = result.sub(/\n```\z/, "")
      elsif result.end_with?("\r\n```")
        result = result.sub(/\r\n```\z/, "")
      elsif result.end_with?("```")
        result = result.sub(/```\z/, "")
      end

      result.strip
    end

    # Replace nostr: URIs with web links using the user's link templates.
    # Prefers nevent1 > note1 > hex for event identifiers.
    def self.replace_nostr_uris(content, user)
      return content if content.blank?

      event_template = user.event_link_template
      naddr_template = user.naddr_link_template

      content.gsub(/nostr:(note1[a-z0-9]+|nevent1[a-z0-9]+|naddr1[a-z0-9]+|[0-9a-f]{64})/i) do |match|
        identifier = match.sub(/\Anostr:/i, "")
        parsed = Nostr::KeyConverter.parse_nostr_identifier(identifier)

        if parsed.nil?
          match
        elsif parsed[:type] == :naddr
          naddr_template.gsub("{naddr}", identifier)
        elsif parsed[:type] == :nevent
          event_template.gsub("{eventid}", identifier)
        elsif parsed[:type] == :note
          # Try to find event and get nevent with relay hints
          event = Event.find_by(external_id: parsed[:event_id])
          if event&.nevent_id.present?
            event_template.gsub("{eventid}", event.nevent_id)
          else
            event_template.gsub("{eventid}", identifier)
          end
        elsif parsed[:type] == :hex && parsed[:event_id].present?
          # Try to convert to nevent, fallback to note1
          event = Event.find_by(external_id: parsed[:event_id])
          if event&.nevent_id.present?
            event_template.gsub("{eventid}", event.nevent_id)
          else
            note_id = Nostr::KeyConverter.hex_to_note(parsed[:event_id])
            event_template.gsub("{eventid}", note_id || parsed[:event_id])
          end
        else
          match
        end
      end
    end
  end
end
