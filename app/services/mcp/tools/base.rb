# frozen_string_literal: true

module Mcp
  module Tools
    class Base
      class InvalidParams < StandardError; end
      class AppError < StandardError; end

      MAX_LIMIT = 200

      def initialize(user, args)
        @user = user
        @args = (args || {}).with_indifferent_access
      end

      def self.description
        raise NotImplementedError
      end

      def self.input_schema
        raise NotImplementedError
      end

      def call
        raise NotImplementedError
      end

      private

      attr_reader :user, :args

      def fetch_int(key, default:, min: 0, max: MAX_LIMIT)
        v = args[key]
        return default if v.nil? || v == ""
        i = Integer(v)
        i.clamp(min, max)
      rescue ArgumentError, TypeError
        raise InvalidParams, "#{key} must be an integer"
      end

      def fetch_bool(key, default:)
        v = args[key]
        return default if v.nil?
        ActiveModel::Type::Boolean.new.cast(v)
      end

      def fetch_time(key, default:)
        v = args[key]
        return default if v.blank?
        Time.iso8601(v.to_s)
      rescue ArgumentError
        raise InvalidParams, "#{key} must be ISO8601"
      end

      def find_user_channel!(channel_id)
        raise InvalidParams, "channel_id required" if channel_id.blank?
        user.channels.find_by!(id: channel_id)
      end

      def find_user_event!(event_id)
        raise InvalidParams, "event_id required" if event_id.blank?
        user.events.find_by!(id: event_id)
      end

      def find_user_source!(source_id)
        raise InvalidParams, "source_id required" if source_id.blank?
        user.sources.find_by!(id: source_id)
      end

      def serialize_channel(channel, counts: nil)
        {
          id: channel.id,
          name: channel.name,
          description: channel.description,
          language: channel.language,
          prompt: channel.prompt,
          relevance_threshold: channel.relevance_threshold,
          total_events: counts&.dig(:total),
          unused_events: counts&.dig(:unused),
          used_events: counts&.dig(:used)
        }.compact
      end

      def serialize_event(event, channel_ratings: nil, include_links: true)
        {
          id: event.id,
          source: serialize_source(event.source),
          event_type: event.event_type,
          external_id: event.external_id,
          source_identifier: event.source_identifier,
          source_link: event.source_link(user),
          published_at: event.published_at&.iso8601,
          content: event.content,
          content_resolved: event.content_for_embedding,
          linked_urls: include_links ? event.linked_contents.pluck(:url) : nil,
          channel_ratings: channel_ratings
        }.compact
      end

      def serialize_source(source)
        return nil unless source
        {
          id: source.id,
          name: source.name,
          type: source.source_type,
          identifier: source.identifier
        }
      end

      def serialize_channel_event(ce)
        {
          channel_id: ce.channel_id,
          channel_name: ce.channel.name,
          score: ce.relevance_score,
          reason: ce.relevance_reason,
          used: ce.used,
          used_at: ce.used_at&.iso8601
        }
      end
    end
  end
end
