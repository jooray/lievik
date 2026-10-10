# frozen_string_literal: true

module Api
  module V1
    class DashboardController < BaseController
      requires_paid_access only: :rate_all

      def show
        # Sweep this user's stale logs first, like the web dashboard: the
        # recurring sweep can itself be down.
        current_user.activity_logs.mark_stale_as_failed!
        recent = current_user.events.includes(:source, channel_events: :channel).recent.limit(20)

        render json: {
          stats: Users::Stats.for(current_user),
          active_jobs: current_user.activity_logs.active.map { |log| Serializers.activity_log(log) },
          recent_events: EventSerializer.many(recent, serialization_context)
        }
      end

      def rate_all
        count = Channels::RateAll.call(current_user)
        render json: { notice: Channels::RateAll.notice(count), queued_channels: count }
      end
    end
  end
end
