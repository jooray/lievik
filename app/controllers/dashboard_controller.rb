# frozen_string_literal: true

class DashboardController < ApplicationController
  requires_paid_access only: :rate_all

  def index
    # Same counters as the app API (Users::Stats).
    stats = Users::Stats.for(current_user)
    @sources_count = stats[:sources]
    @channels_count = stats[:channels]
    @events_count = stats[:events]
    @embedded_count = stats[:embedded]

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
    count = Channels::RateAll.call(current_user)
    redirect_to dashboard_path, notice: Channels::RateAll.notice(count)
  end
end
