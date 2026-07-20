# frozen_string_literal: true

class DashboardController < ApplicationController
  def index
    # Exclude manual sources to match what's shown on the sources index page
    @sources_count = current_user.sources.where.not(source_type: :manual).count
    @channels_count = current_user.channels.count
    @events_count = current_user.events.count
    @embedded_count = current_user.events.where.not(embedding: nil).count

    # Active background jobs. Sweep this user's stale logs first: the recurring
    # sweep is the primary path, but it rides on a scheduler that can itself be
    # down (and once was, for days), and the visible symptom is a dashboard full
    # of phantom "running" cards. Doing it on read makes the UI self-healing.
    current_user.activity_logs.mark_stale_as_failed!
    @active_jobs = current_user.activity_logs.active

    # Recent events with top channel relevance pre-loaded
    @recent_events = current_user.events
      .includes(:source, channel_events: :channel)
      .recent
      .limit(20)
  end

  def rate_all
    channels = current_user.channels
    channels.each { |channel| RateEventsJob.perform_later(channel.id) }
    redirect_to dashboard_path, notice: "Rating jobs queued for #{channels.count} channels."
  end
end
