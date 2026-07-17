# frozen_string_literal: true

module Mcp
  module Tools
    class ListChannels < Base
      def self.description
        "List all marketing channels owned by the authenticated user, with their relevance criteria, threshold, and event counts."
      end

      def self.input_schema
        { type: "object", properties: {}, additionalProperties: false }
      end

      def call
        channels = user.channels.order(:name).to_a

        # Aggregate channel_event counts in one query each, keyed by channel_id
        total_by_channel = ChannelEvent.where(channel_id: channels.map(&:id)).group(:channel_id).count
        unused_by_channel = ChannelEvent.where(channel_id: channels.map(&:id), used: false).group(:channel_id).count

        result = channels.map do |c|
          total = total_by_channel[c.id] || 0
          unused = unused_by_channel[c.id] || 0
          serialize_channel(c, counts: { total: total, unused: unused, used: total - unused })
        end

        { channels: result }
      end
    end
  end
end
