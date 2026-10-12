# frozen_string_literal: true

class ChannelContentsController < ApplicationController
  include ActionController::Live
  include SseStreaming

  before_action :set_channel
  before_action :set_channel_content, only: [ :show, :edit, :update, :destroy, :generate_stream, :refine_stream, :publish, :revert ]
  before_action :set_events_from_params, only: [ :new, :create ]
  # After set_channel_content, so a 404 wins and a denied generation saves no version.
  requires_paid_ai kind: "content", only: :generate_stream
  requires_paid_ai kind: "content", prompt: :user_prompt, only: :refine_stream

  def index
    @channel_contents = @channel.channel_contents.recent
    @drafts = @channel_contents.drafts
    @published = @channel_contents.published_content
    @event_counts = ChannelContentEvent.where(channel_content_id: @channel.channel_contents.select(:id))
      .group(:channel_content_id)
      .count
  end

  def show
    @events = @channel_content.events.includes(:source)
  end

  def new
    @channel_content = @channel.channel_contents.build
  end

  def create
    @channel_content = ChannelContents::Editor.create(@channel, current_user, channel_content_params, params[:event_ids])

    if @channel_content.persisted?
      # Redirect to edit page with auto_generate flag to trigger streaming
      redirect_to edit_channel_content_path(@channel, @channel_content, auto_generate: true),
                  notice: t(".notice")
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

    # Saves a version first when the text changes (shared with the app API).
    if ChannelContents::Editor.update(@channel_content, channel_content_params)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("content-status", partial: "content_status"),
            turbo_stream.replace("generation-prompt-panel", partial: "generation_prompt_panel")
          ]
        end
        format.html { redirect_to edit_channel_content_path(@channel, @channel_content), notice: t(".notice") }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @channel_content.destroy
    redirect_to channel_contents_path(@channel), notice: t(".notice")
  end

  # POST /channels/:channel_id/contents/:id/generate_stream
  # SSE endpoint for streaming AI content generation (ChannelContents::Generation,
  # shared with the app API)
  def generate_stream
    stream_sse { |sse| ChannelContents::Generation.new(@channel_content, current_user).generate(sse) }
  end

  # POST /channels/:channel_id/contents/:id/refine_stream
  # SSE endpoint for streaming AI content refinement
  def refine_stream
    stream_sse { |sse| ChannelContents::Generation.new(@channel_content, current_user).refine(sse, params[:user_prompt]) }
  end

  # POST /channels/:channel_id/contents/:id/publish
  def publish
    @channel_content.publish!

    redirect_to channel_content_path(@channel, @channel_content),
                notice: t(".notice")
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
        format.html { redirect_to edit_channel_content_path(@channel, @channel_content), notice: t(".notice") }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "content-status",
            partial: "content_status",
            locals: { error: t(".no_previous") }
          )
        end
        format.html { redirect_to edit_channel_content_path(@channel, @channel_content), alert: t(".no_previous") }
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
    event_ids = ChannelContents::Editor.parse_event_ids(params[:event_ids])
    @selected_events = current_user.events.where(id: event_ids).includes(:source) if event_ids.present?
    @selected_events ||= []
  end

  def channel_content_params
    params.require(:channel_content).permit(:title, :content, :generation_prompt)
  end
end
