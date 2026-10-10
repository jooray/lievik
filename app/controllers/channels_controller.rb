# frozen_string_literal: true

class ChannelsController < ApplicationController
  # Each card resolves nostr: references and renders event content, so a large
  # page is genuinely expensive to build. 100 was noticeably slow on real data.
  PER_PAGE = 50

  MAX_BULK_RATE_EVENTS = RateEventsJob::MAX_BULK_RATE_EVENTS

  # Whitelist (ChannelEvents::Listing): the value picks an ORDER BY, so it must
  # never come straight from params. "relevance" is the default and is left
  # out of generated URLs.
  SORT_OPTIONS = ChannelEvents::Listing::SORT_OPTIONS
  DEFAULT_SORT = ChannelEvents::Listing::DEFAULT_SORT

  before_action :set_channel, only: [:show, :edit, :update, :destroy, :settings, :update_settings, :rate]
  requires_paid_access only: :rate

  def index
    @channels = current_user.channels.order(:name)
    @pending_event_counts = Channels::PendingCounts.for(@channels)
  end

  def show
    @show_used = params[:show_used] == "true"
    @search_query = params[:search]
    @selected_event_id = params[:selected_event]&.to_i

    # Same listing as the app API (ChannelEvents::Listing).
    listing = ChannelEvents::Listing.new(@channel, show_used: @show_used, search: @search_query, sort: params[:sort])
    @threshold = listing.threshold
    @sort = listing.sort
    @channel_events = listing.scope.page(params[:page]).per(PER_PAGE)
    @used_count = listing.counts[:used]
    @unused_count = listing.counts[:unused]

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
      queued = Channels::InitialRating.queue(@channel)
      redirect_to @channel, notice: Channels::InitialRating.created_notice(queued)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @channel.update(channel_params)
      redirect_to @channel, notice: t(".notice")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @channel.destroy
    redirect_to channels_path, notice: t(".notice")
  end

  def settings
  end

  def update_settings
    if @channel.update(settings_params)
      redirect_to @channel, notice: t(".notice")
    else
      render :settings, status: :unprocessable_entity
    end
  end

  def rate
    @channel.rate_new_events!
    redirect_to @channel, notice: t(".notice")
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
end
