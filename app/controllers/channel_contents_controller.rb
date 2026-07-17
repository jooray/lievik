# frozen_string_literal: true

class ChannelContentsController < ApplicationController
  include ActionController::Live

  before_action :set_channel
  before_action :set_channel_content, only: [:show, :edit, :update, :destroy, :generate, :generate_stream, :refine, :refine_stream, :publish, :revert]
  before_action :set_events_from_params, only: [:new, :create]

  def index
    @channel_contents = @channel.channel_contents.includes(:events).recent
    @drafts = @channel_contents.drafts
    @published = @channel_contents.published_content
  end

  def show
    @events = @channel_content.events.includes(:source)
  end

  def new
    @channel_content = @channel.channel_contents.build
  end

  def create
    @channel_content = @channel.channel_contents.build(channel_content_params)
    @channel_content.user = current_user

    if @channel_content.save
      # Associate selected events
      attach_events(@channel_content, params[:event_ids])

      # Redirect to edit page with auto_generate flag to trigger streaming
      redirect_to edit_channel_content_path(@channel, @channel_content, auto_generate: true),
                  notice: "Content draft created. Generating content..."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @events = @channel_content.events.includes(:source, :linked_contents)
  end

  def update
    if params[:generation_prompt].present? && params[:channel_content].blank?
      params[:channel_content] = { generation_prompt: params[:generation_prompt] }
    end

    # Save current version before updating
    submitted_content = params.dig(:channel_content, :content)
    @channel_content.add_version(@channel_content.content) if !submitted_content.nil? && @channel_content.content != submitted_content

    if @channel_content.update(channel_content_params)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("content-status", partial: "content_status"),
            turbo_stream.replace("generation-prompt-panel", partial: "generation_prompt_panel")
          ]
        end
        format.html { redirect_to edit_channel_content_path(@channel, @channel_content), notice: "Content saved." }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @channel_content.destroy
    redirect_to channel_contents_path(@channel), notice: "Content deleted."
  end

  # POST /channels/:channel_id/contents/:id/generate
  # Generate content from source events using AI
  def generate
    events = @channel_content.events.includes(:source, :linked_contents)

    if events.empty?
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "editor-container",
            partial: "editor_container",
            locals: { error: "No source events found. Please add events first." }
          )
        end
        format.html { redirect_to edit_channel_content_path(@channel, @channel_content), alert: "No source events found." }
      end
      return
    end

    # Save current version before generating new content
    @channel_content.add_version(@channel_content.content) if @channel_content.content.present?

    service = Ai::ContentBuilderService.new(
      channel: @channel,
      events: events,
      title: @channel_content.title,
      generation_prompt: @channel_content.generation_prompt
    )
    result = service.generate

    # Humanize if enabled and generation succeeded
    if result[:content].present? && service.humanize_enabled?
      humanize_result = service.humanize(result[:content])
      result[:content] = humanize_result[:content] if humanize_result[:content].present?
    end

    if result[:error]
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "editor-container",
            partial: "editor_container",
            locals: { error: "AI generation failed: #{result[:error]}" }
          )
        end
        format.html { redirect_to edit_channel_content_path(@channel, @channel_content), alert: "AI generation failed: #{result[:error]}" }
      end
    else
      @channel_content.update!(content: result[:content])

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("editor-container", partial: "editor_container"),
            turbo_stream.replace("content-status", partial: "content_status")
          ]
        end
        format.html { redirect_to edit_channel_content_path(@channel, @channel_content), notice: "Content generated successfully." }
      end
    end
  end

  # GET /channels/:channel_id/contents/:id/generate_stream
  # SSE endpoint for streaming AI content generation
  def generate_stream
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no" # Disable nginx buffering

    events = @channel_content.events.includes(:source, :linked_contents)

    if events.empty?
      response.stream.write "event: error\ndata: {\"message\": \"No source events found\"}\n\n"
      response.stream.close
      return
    end

    # Save current version before generating
    @channel_content.add_version(@channel_content.content) if @channel_content.content.present?

    service = Ai::ContentBuilderService.new(
      channel: @channel,
      events: events,
      title: @channel_content.title,
      generation_prompt: @channel_content.generation_prompt
    )
    full_content = ""

    begin
      # Phase 1: Generation
      response.stream.write "event: phase\ndata: #{({ phase: "generating" }).to_json}\n\n"

      generation_result = service.generate_stream do |chunk|
        full_content += chunk
        # Send chunk as SSE event
        escaped_chunk = chunk.to_json
        response.stream.write "event: chunk\ndata: #{escaped_chunk}\n\n"
      end

      if generation_result[:error]
        response.stream.write "event: error\ndata: #{({ message: generation_result[:error] }).to_json}\n\n"
        return
      end

      full_content = generation_result[:content] if generation_result[:content].present?

      # Phase 2: Humanization (if enabled)
      if service.humanize_enabled?
        response.stream.write "event: phase\ndata: #{({ phase: "humanizing" }).to_json}\n\n"

        humanized_content = ""
        service.humanize_stream(full_content) do |chunk|
          humanized_content += chunk
          response.stream.write "event: chunk\ndata: #{chunk.to_json}\n\n"
        end
        full_content = humanized_content if humanized_content.present?
      end

      # Save the completed content (post-process to strip fences and replace nostr URIs)
      @channel_content.update!(content: post_process_content(full_content))

      # Send completion event
      response.stream.write "event: complete\ndata: {\"success\": true}\n\n"
    rescue Ai::Client::ApiError => e
      Rails.logger.error("Streaming generation failed: #{e.message}")
      response.stream.write "event: error\ndata: #{{ message: e.message }.to_json}\n\n"
    rescue => e
      Rails.logger.error("Streaming error: #{e.message}")
      response.stream.write "event: error\ndata: #{{ message: "Unexpected error occurred" }.to_json}\n\n"
    ensure
      response.stream.close
    end
  end

  # POST /channels/:channel_id/contents/:id/refine
  # Refine content with AI based on user prompt
  def refine
    user_prompt = params[:user_prompt]
    existing_content = @channel_content.content

    if user_prompt.blank?
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "ai-prompt-modal",
            partial: "ai_prompt_modal",
            locals: { error: "Please provide instructions for the AI." }
          )
        end
        format.html { redirect_to edit_channel_content_path(@channel, @channel_content), alert: "Please provide instructions." }
      end
      return
    end

    # Save current version before refining
    @channel_content.add_version(existing_content) if existing_content.present?

    events = @channel_content.events.includes(:source, :linked_contents)
    service = Ai::ContentBuilderService.new(channel: @channel, events: events)
    result = service.refine(existing_content: existing_content, user_prompt: user_prompt)

    # Humanize if enabled and refinement succeeded
    if result[:content].present? && service.humanize_enabled?
      humanize_result = service.humanize(result[:content])
      result[:content] = humanize_result[:content] if humanize_result[:content].present?
    end

    if result[:error]
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "editor-container",
            partial: "editor_container",
            locals: { error: "AI refinement failed: #{result[:error]}" }
          )
        end
        format.html { redirect_to edit_channel_content_path(@channel, @channel_content), alert: "AI refinement failed: #{result[:error]}" }
      end
    else
      @channel_content.update!(content: result[:content])

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("editor-container", partial: "editor_container"),
            turbo_stream.replace("content-status", partial: "content_status"),
            turbo_stream.replace("ai-prompt-modal", partial: "ai_prompt_modal", locals: { show: false })
          ]
        end
        format.html { redirect_to edit_channel_content_path(@channel, @channel_content), notice: "Content refined successfully." }
      end
    end
  end

  # GET /channels/:channel_id/contents/:id/refine_stream
  # SSE endpoint for streaming AI content refinement
  def refine_stream
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    user_prompt = params[:user_prompt]
    existing_content = @channel_content.content

    if user_prompt.blank?
      response.stream.write "event: error\ndata: #{({ message: "Please provide instructions for the AI." }).to_json}\n\n"
      response.stream.close
      return
    end

    if existing_content.blank?
      response.stream.write "event: error\ndata: #{({ message: "No content to refine." }).to_json}\n\n"
      response.stream.close
      return
    end

    # Save current version before refining
    @channel_content.add_version(existing_content)

    events = @channel_content.events.includes(:source, :linked_contents)
    service = Ai::ContentBuilderService.new(channel: @channel, events: events)
    full_content = ""

    begin
      # Phase 1: Refinement
      response.stream.write "event: phase\ndata: #{({ phase: "refining" }).to_json}\n\n"

      refinement_result = service.refine_stream(existing_content: existing_content, user_prompt: user_prompt) do |chunk|
        full_content += chunk
        escaped_chunk = chunk.to_json
        response.stream.write "event: chunk\ndata: #{escaped_chunk}\n\n"
      end

      if refinement_result[:error]
        response.stream.write "event: error\ndata: #{({ message: refinement_result[:error] }).to_json}\n\n"
        return
      end

      full_content = refinement_result[:content] if refinement_result[:content].present?

      # Phase 2: Humanization (if enabled)
      if service.humanize_enabled?
        response.stream.write "event: phase\ndata: #{({ phase: "humanizing" }).to_json}\n\n"

        humanized_content = ""
        service.humanize_stream(full_content) do |chunk|
          humanized_content += chunk
          response.stream.write "event: chunk\ndata: #{chunk.to_json}\n\n"
        end
        full_content = humanized_content if humanized_content.present?
      end

      # Save the completed content (post-process to strip fences and replace nostr URIs)
      @channel_content.update!(content: post_process_content(full_content))

      response.stream.write "event: complete\ndata: #{({ success: true }).to_json}\n\n"
    rescue Ai::Client::ApiError => e
      Rails.logger.error("Streaming refinement failed: #{e.message}")
      response.stream.write "event: error\ndata: #{({ message: e.message }).to_json}\n\n"
    rescue => e
      Rails.logger.error("Streaming error: #{e.message}")
      response.stream.write "event: error\ndata: #{({ message: "Unexpected error occurred" }).to_json}\n\n"
    ensure
      response.stream.close
    end
  end

  # POST /channels/:channel_id/contents/:id/publish
  def publish
    @channel_content.publish!

    redirect_to channel_content_path(@channel, @channel_content),
                notice: "Content published and source events marked as used."
  end

  # POST /channels/:channel_id/contents/:id/revert
  def revert
    if @channel_content.revert_to_previous!
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("editor-container", partial: "editor_container"),
            turbo_stream.replace("content-status", partial: "content_status")
          ]
        end
        format.html { redirect_to edit_channel_content_path(@channel, @channel_content), notice: "Reverted to previous version." }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "content-status",
            partial: "content_status",
            locals: { error: "No previous version available." }
          )
        end
        format.html { redirect_to edit_channel_content_path(@channel, @channel_content), alert: "No previous version available." }
      end
    end
  end

  private

  def set_channel
    @channel = current_user.channels.find(params[:channel_id])
  end

  def set_channel_content
    @channel_content = @channel.channel_contents.find(params[:id])
  end

  def set_events_from_params
    event_ids = parse_event_ids(params[:event_ids])
    @selected_events = Event.where(id: event_ids).includes(:source) if event_ids.present?
    @selected_events ||= []
  end

  def parse_event_ids(event_ids_param)
    return [] if event_ids_param.blank?

    if event_ids_param.is_a?(String)
      JSON.parse(event_ids_param)
    else
      Array.wrap(event_ids_param).reject(&:blank?)
    end
  rescue JSON::ParserError
    []
  end

  def channel_content_params
    params.require(:channel_content).permit(:title, :content, :generation_prompt)
  end

  def attach_events(channel_content, event_ids_param)
    event_ids = parse_event_ids(event_ids_param)
    return if event_ids.empty?

    event_ids.each do |event_id|
      channel_content.channel_content_events.create(event_id: event_id)
    end
  end

  # Post-process AI-generated content: strip markdown fences and replace nostr: URIs
  def post_process_content(content)
    return content if content.blank?

    result = strip_markdown_fences(content)
    replace_nostr_uris(result)
  end

  # Strip markdown code fences from the beginning and end of AI responses
  def strip_markdown_fences(content)
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

  # Replace nostr: URIs with web links using the user's link templates
  # Prefers nevent1 > note1 > hex for event identifiers
  def replace_nostr_uris(content)
    return content if content.blank?

    event_template = current_user.event_link_template
    naddr_template = current_user.naddr_link_template

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
