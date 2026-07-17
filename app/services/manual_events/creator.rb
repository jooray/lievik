# frozen_string_literal: true

module ManualEvents
  class Creator
    Result = Struct.new(:event, :errors, keyword_init: true) do
      def success?
        event&.persisted? && (errors.nil? || errors.empty?)
      end
    end

    def initialize(user, content:, published_at: nil)
      @user = user
      @content = content.to_s
      @published_at = published_at || Time.current
    end

    def call
      manual_source = @user.sources.find_by(source_type: :manual)
      return Result.new(event: nil, errors: ["No manual source configured for user"]) unless manual_source

      event = manual_source.events.build(
        content: @content,
        published_at: @published_at,
        event_type: :original,
        external_id: SecureRandom.uuid
      )

      if event.save
        linked_contents = Links::ExtractionService.new(event).extract_and_save
        unfetched_ids = linked_contents.select { |lc| lc.fetched_at.nil? }.map(&:id)
        FetchLinksJob.perform_later(unfetched_ids) if unfetched_ids.any?

        @user.channels.find_each do |channel|
          RateEventsJob.perform_later(channel.id, [event.id])
        end

        Result.new(event: event, errors: [])
      else
        Result.new(event: event, errors: event.errors.full_messages)
      end
    end
  end
end
