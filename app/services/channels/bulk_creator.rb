# frozen_string_literal: true

module Channels
  # Creates the channels (and content templates) accepted from the AI channel
  # chat's proposal cards, then back-rates recent events for each. Shared by
  # ChannelAiChatController#bulk_create and the app API.
  class BulkCreator
    Result = Struct.new(:ok, :channels, :error, keyword_init: true) do
      def ok? = ok
      def count = channels.size
    end

    def initialize(user, channels:, templates: [])
      @user = user
      @channels_data = Array(channels).map { |c| indifferent(c) }
      @templates_data = Array(templates).map { |t| indifferent(t) }
    end

    def call
      return Result.new(ok: false, channels: [], error: I18n.t("channel_ai_chat.errors.no_channels")) if @channels_data.empty?

      created = []
      ActiveRecord::Base.transaction do
        @templates_data.each do |template|
          next if template[:name].blank? || template[:template].blank?
          # Skip if a template with the same name already exists
          next if @user.content_templates_list.any? { |t| t["name"] == template[:name] }

          @user.add_content_template(name: template[:name], template: template[:template])
        end

        @channels_data.each do |data|
          created << @user.channels.create!(
            name: data[:name],
            description: data[:description],
            language: data[:language] || "en",
            prompt: data[:prompt],
            content_style: data[:content_style],
            content_language: data[:content_language] || data[:language],
            settings: {
              "relevance_threshold" => (data.dig(:settings, :relevance_threshold) || 50).to_i,
              "humanize_output" => data.dig(:settings, :humanize_output) != false
            }
          )
        end
      end

      # Outside the transaction: jobs must not see uncommitted channels.
      created.each { |channel| Channels::InitialRating.queue(channel) }

      Result.new(ok: true, channels: created)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(ok: false, channels: [], error: e.message)
    end

    private

    def indifferent(value)
      value = value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
      value.respond_to?(:to_h) ? value.to_h.with_indifferent_access : {}.with_indifferent_access
    end
  end
end
