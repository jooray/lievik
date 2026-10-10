# frozen_string_literal: true

module Api
  module V1
    # A channel's curation queue (the web channel page) and its bulk actions.
    class ChannelEventsController < BaseController
      before_action :set_channel
      requires_paid_access only: :rate

      def index
        listing = ChannelEvents::Listing.new(@channel, show_used: truthy_param?(:show_used), search: params[:search], sort: params[:sort])
        page = paginate(listing.scope.includes(event: { channel_events: :channel }))
        events = EventSerializer.many(page.map(&:event), serialization_context)

        render json: {
          items: page.each_with_index.map { |ce, i| { channel_event: Serializers.channel_event(ce), event: events[i] } },
          meta: pagination_meta(page),
          used_count: listing.counts[:used],
          unused_count: listing.counts[:unused],
          threshold: listing.threshold.to_i
        }
      end

      def mark_used
        respond_with bulk.mark_used(params[:event_ids])
      end

      def mark_unused
        respond_with bulk.mark_unused(params[:event_ids])
      end

      def rate
        respond_with bulk.rate(params[:event_ids])
      end

      private

      def set_channel
        @channel = current_user.channels.find(params[:channel_id])
      end

      def bulk
        ChannelEvents::BulkActions.new(@channel, current_user)
      end

      def respond_with(result)
        return render_alert(result.message, code: "no_selection") unless result.ok?

        render json: { notice: result.message, count: result.count }
      end
    end
  end
end
