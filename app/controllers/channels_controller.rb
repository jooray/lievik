# frozen_string_literal: true

class ChannelsController < ApplicationController
  # Each card resolves nostr: references and renders event content, so a large
  # page is genuinely expensive to build. 100 was noticeably slow on real data.
  PER_PAGE = 50

  MAX_BULK_RATE_EVENTS = RateEventsJob::MAX_BULK_RATE_EVENTS

  before_action :set_channel, only: [:show, :edit, :update, :destroy, :settings, :update_settings, :rate]

  def index
    @channels = current_user.channels.order(:name)
    @pending_event_counts = pending_event_counts(@channels)
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
      # Escape LIKE metacharacters — an unescaped "%" would match every row.
      # "!" as the escape char behaves the same on SQLite and MariaDB.
      pattern = ActiveRecord::Base.sanitize_sql_like(@search_query.to_s, "!")
      @channel_events = @channel_events.joins(:event).where("events.content LIKE ? ESCAPE '!'", "%#{pattern}%")
    end

    # Separate used and unused events
    if @show_used
      # Show all events, with unused first, then used at bottom
      @channel_events = @channel_events.order(used: :asc).by_relevance.page(params[:page]).per(PER_PAGE)
    else
      # Only show unused events
      @channel_events = @channel_events.unused.by_relevance.page(params[:page]).per(PER_PAGE)
    end

    # One grouped query instead of two COUNTs. `used` is a boolean, so the keys
    # come back as true/false (SQLite returns 0/1, hence the coercion).
    counts = @channel.channel_events.above_threshold(@threshold).group(:used).count
    @used_count = 0
    @unused_count = 0
    counts.each do |used, count|
      ActiveModel::Type::Boolean.new.cast(used) ? @used_count += count : @unused_count += count
    end

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
      queued = queue_initial_rating(@channel)
      notice = if queued.zero?
        "Channel created successfully."
      elsif queued >= MAX_BULK_RATE_EVENTS
        "Channel created successfully. Rating the #{queued} most recent events in the background — use Rate to score older ones."
      else
        "Channel created successfully. Rating #{queued} recent events in the background."
      end
      redirect_to @channel, notice: notice
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

  # "Pending" must mean the same thing here as on the channel page: unused AND
  # above that channel's own relevance threshold. Thresholds live in a JSON
  # settings column, so instead of a (DB-specific) json_extract comparison we
  # fold the already-loaded thresholds into a single OR'd predicate — still one
  # query, no N+1, and identical on SQLite and MariaDB.
  def pending_event_counts(channels)
    thresholds = channels.map { |c| [c.id, c.relevance_threshold] }
    return {} if thresholds.empty?

    predicate = thresholds.map do |id, threshold|
      ChannelEvent.sanitize_sql_array(
        ["(channel_events.channel_id = ? AND channel_events.relevance_score >= ?)", id, threshold]
      )
    end.join(" OR ")

    ChannelEvent.unused.where(predicate).group(:channel_id).count
  end

  def set_channel
    @channel = current_user.channels.find(params[:id])
  end

  def channel_params
    params.require(:channel).permit(:name, :description, :language, :prompt)
  end

  def settings_params
    params.require(:channel).permit(:content_prompt, :content_language, :content_style, settings: [:relevance_threshold, :humanize_output])
  end

  # Rating an event costs up to 3 paid AI calls, so a brand-new channel only
  # back-rates a bounded, most-recent slice; the rest can be rated later.
  def queue_initial_rating(channel)
    recent_event_ids = current_user.events
      .where("events.published_at >= ?", 3.months.ago)
      .order(published_at: :desc)
      .limit(MAX_BULK_RATE_EVENTS)
      .pluck(:id)

    RateEventsJob.enqueue_batches(channel.id, recent_event_ids)
  end
end
