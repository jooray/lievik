# frozen_string_literal: true

module Api
  module V1
    class ManualEventsController < BaseController
      def create
        content = params[:content].presence || params.dig(:event, :content)
        result = ManualEvents::Creator.new(current_user, content: content).call
        unless result.success?
          return render_invalid(result.event) if result.event

          return render_error(:unprocessable_content, "invalid", result.errors.to_sentence)
        end

        event = current_user.events.includes(:source, channel_events: :channel).find(result.event.id)
        render json: { event: EventSerializer.one(event, serialization_context), notice: t("manual_events.create.added") }, status: :created
      end
    end
  end
end
