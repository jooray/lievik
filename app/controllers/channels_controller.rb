# frozen_string_literal: true

class ChannelsController < ApplicationController
  before_action :set_channel, only: [:show, :edit, :update, :destroy, :settings, :update_settings, :rate]

  def index
    @channels = current_user.channels.order(:name)
  end

  def show
    @threshold = @channel.relevance_threshold
    @show_used = params[:show_used] == "true"
    @search_query = params[:search]
    @selected_event_id = params[:selected_event]&.to_i

    @channel_events = @channel.channel_events
      .includes(event: :source)
      .above_threshold(@threshold)

    # Apply search filter
    if @search_query.present?
      @channel_events = @channel_events.joins(:event).where("events.content LIKE ?", "%#{@search_query}%")
    end

    # Separate used and unused events
    if @show_used
      # Show all events, with unused first, then used at bottom
      @channel_events = @channel_events.order(used: :asc).by_relevance.page(params[:page]).per(100)
    else
      # Only show unused events
      @channel_events = @channel_events.unused.by_relevance.page(params[:page]).per(100)
    end

    @used_count = @channel.channel_events.above_threshold(@threshold).used.count
    @unused_count = @channel.channel_events.above_threshold(@threshold).unused.count

    # Find the selected channel_event if specified and always put it at top
    if @selected_event_id
      @selected_channel_event = @channel.channel_events.includes(event: :source).find_by(event_id: @selected_event_id)
      if @selected_channel_event
        # Remove from current position (if present) and prepend to top
        other_events = @channel_events.to_a.reject { |ce| ce.id == @selected_channel_event.id }
        @channel_events_with_selected = [@selected_channel_event] + other_events
      end
    end
  end

  def new
    @channel = current_user.channels.build(
      prompt: Channel.default_prompt_template,
      content_style: current_user.default_content_style
    )
  end

  def create
    @channel = current_user.channels.build(channel_params)

    if @channel.save
      # Auto-rate recent events (past 3 months) for the new channel
      queue_initial_rating(@channel)
      redirect_to @channel, notice: "Channel created successfully. Rating recent events in the background."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @channel.update(channel_params)
      redirect_to @channel, notice: "Channel updated"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @channel.destroy
    redirect_to channels_path, notice: "Channel deleted"
  end

  def settings
  end

  def update_settings
    if @channel.update(settings_params)
      redirect_to @channel, notice: "Settings updated"
    else
      render :settings, status: :unprocessable_entity
    end
  end

  def rate
    @channel.rate_new_events!
    redirect_to @channel, notice: "Rating job queued. Events will be scored in the background."
  end

  private

  def set_channel
    @channel = current_user.channels.find(params[:id])
  end

  def channel_params
    params.require(:channel).permit(:name, :description, :language, :prompt)
  end

  def settings_params
    params.require(:channel).permit(:content_prompt, :content_language, :content_style, settings: [:relevance_threshold, :humanize_output])
  end

  def queue_initial_rating(channel)
    # Get event IDs from the past 3 months
    recent_event_ids = current_user.sources
      .joins(:events)
      .where("events.published_at >= ?", 3.months.ago)
      .pluck("events.id")

    return if recent_event_ids.empty?

    # Queue rating job with these event IDs
    RateEventsJob.perform_later(channel.id, recent_event_ids)
  end
end
