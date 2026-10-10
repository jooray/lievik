# frozen_string_literal: true

module Api
  module V1
    # The "all events" list, one event, and its rating/used actions.
    class EventsController < BaseController
      requires_paid_access only: :rate

      def index
        events = paginate(Events::Filter.call(current_user, filter_params).includes(:source, channel_events: :channel))
        render json: {
          events: EventSerializer.many(events, serialization_context),
          meta: pagination_meta(events),
          filter_sources: Events::Filter.sources(current_user).map { |s| { id: s.id, name: s.display_label, source_type: s.source_type } }
        }
      end

      def show
        event = current_user.events.includes(:source, :linked_contents, channel_events: :channel).find(params[:id])
        channel_events = event.channel_events.sort_by { |ce| -(ce.relevance_score || -1) }
        render json: {
          event: EventSerializer.one(event, serialization_context),
          channel_events: channel_events.map { |ce| Serializers.channel_event(ce, channel_name: true) },
          linked_contents: event.linked_contents.map do |lc|
            { url: lc.url, title: lc.title, summary: lc.metadata.is_a?(Hash) ? lc.metadata["summary"] : nil, fetched_at: Context.iso(lc.fetched_at) }
          end
        }
      end

      # An explicit selection, or the filtered set (Events::BulkRate, capped).
      def rate
        result = Events::BulkRate.new(current_user, event_ids: params[:event_ids], filter: filter_params).call
        return render_alert(result.message, code: "no_match") unless result.ok?

        render json: { notice: result.message, count: result.count }
      end

      def mark_used
        event = current_user.events.find(params[:id])
        result = Events::MarkUsed.call(current_user, event, params[:channel_event_ids])
        return render_alert(result.message, code: "no_selection") unless result.ok?

        render json: { notice: result.message, count: result.count }
      end

      private

      def filter_params
        params.permit(:source_id, :event_type, :search).to_h.compact_blank
      end
    end
  end
end
