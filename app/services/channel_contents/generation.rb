# frozen_string_literal: true

module ChannelContents
  # AI generation and refinement of a draft, streamed as server-sent events
  # (phase → chunk… → [humanizing → chunk…] → complete, or error). Saves a
  # version before overwriting and stores the post-processed result. The web
  # content builder and the app API both stream through this.
  class Generation
    def initialize(channel_content, user)
      @content = channel_content
      @channel = channel_content.channel
      @user = user
    end

    def generate(sse)
      events = source_events
      if events.empty?
        sse.error(I18n.t("channel_contents.errors.no_source_events"))
        return
      end

      # Save current version before generating
      @content.add_version(@content.content) if @content.content.present?

      service = Ai::ContentBuilderService.new(
        channel: @channel,
        events: events,
        title: @content.title,
        generation_prompt: @content.generation_prompt
      )
      run(sse, service, "generating") { |on_chunk| service.generate_stream(&on_chunk) }
    end

    def refine(sse, user_prompt)
      existing_content = @content.content

      if user_prompt.blank?
        sse.error(I18n.t("channel_contents.errors.instructions_required"))
        return
      end

      if existing_content.blank?
        sse.error(I18n.t("channel_contents.errors.nothing_to_refine"))
        return
      end

      # Save current version before refining
      @content.add_version(existing_content)

      service = Ai::ContentBuilderService.new(channel: @channel, events: source_events)
      run(sse, service, "refining") do |on_chunk|
        service.refine_stream(existing_content: existing_content, user_prompt: user_prompt, &on_chunk)
      end
    end

    private

    def source_events
      @content.events.includes(:source, :linked_contents)
    end

    def run(sse, service, phase)
      full_content = +""

      sse.event("phase", { phase: phase })
      result = yield(lambda do |chunk|
        full_content << chunk
        sse.event("chunk", chunk)
      end)

      if result[:error]
        sse.error(result[:error])
        return
      end

      full_content = result[:content] if result[:content].present?

      # Second pass (if the channel wants it): humanization
      if service.humanize_enabled?
        sse.event("phase", { phase: "humanizing" })

        humanized_content = +""
        service.humanize_stream(full_content) do |chunk|
          humanized_content << chunk
          sse.event("chunk", chunk)
        end
        full_content = humanized_content if humanized_content.present?
      end

      @content.update!(content: PostProcessor.call(full_content, @user))
      sse.event("complete", { success: true })
    rescue Ai::Client::ApiError => e
      Rails.logger.error("Streaming #{phase} failed: #{e.message}")
      sse.error(e.message)
    rescue => e
      Rails.logger.error("Streaming error: #{e.message}")
      sse.error(I18n.t("channel_contents.errors.unexpected"))
    end
  end
end
