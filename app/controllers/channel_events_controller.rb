# frozen_string_literal: true

class ChannelEventsController < ApplicationController
  before_action :set_channel
  requires_paid_access only: :bulk_rate

  def bulk_mark_used
    respond_with_result ChannelEvents::BulkActions.new(@channel, current_user).mark_used(params[:event_ids])
  end

  def bulk_rate
    respond_with_result ChannelEvents::BulkActions.new(@channel, current_user).rate(params[:event_ids])
  end

  private

  # Bulk actions redirect back to the list the user was looking at, so the sort
  # has to survive the round trip. Whitelisted for the same reason it is in
  # ChannelsController: it ends up choosing an ORDER BY.
  def sort_param
    params[:sort] if ChannelsController::SORT_OPTIONS.include?(params[:sort]) &&
      params[:sort] != ChannelsController::DEFAULT_SORT
  end

  def respond_with_result(result)
    flash_key = result.ok? ? :notice : :alert
    redirect_to channel_path(@channel, show_used: params[:show_used], sort: sort_param), flash_key => result.message
  end

  def set_channel
    channel_id = params[:channel_id] || params[:id]
    @channel = current_user.channels.find(channel_id)
  end
end
