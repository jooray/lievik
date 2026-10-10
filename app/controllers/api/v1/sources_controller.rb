# frozen_string_literal: true

module Api
  module V1
    class SourcesController < BaseController
      PERMITTED = %i[identifier name description distance source_type
                     settings_include_replies settings_include_reposts settings_import_days].freeze

      before_action :set_source, only: [ :show, :update, :destroy, :refresh, :events ]
      requires_paid_access only: [ :refresh, :refresh_all ]

      # The manual source is left out, like the web sources page.
      def index
        sources = current_user.sources.where.not(source_type: :manual).order(:name).to_a
        counts = Event.where(source_id: sources.map(&:id)).group(:source_id).count
        render json: { sources: sources.map { |s| Serializers.source(s, event_count: counts[s.id] || 0) } }
      end

      def show
        render json: { source: source_json(@source) }
      end

      def events
        events = paginate(@source.events.recent.includes(:source, channel_events: :channel))
        render json: { events: EventSerializer.many(events, serialization_context), meta: pagination_meta(events) }
      end

      def create
        source = current_user.sources.build(source_params)
        return render_invalid(source) unless source.save

        result = Sources::Actions.after_create(source, current_user)
        render json: { source: source_json(source), notice: result.message, importing: result.importing }, status: :created
      end

      def update
        return render_invalid(@source) unless @source.update(source_params)

        render json: { source: source_json(@source), notice: t("sources.update.notice") }
      end

      def destroy
        @source.destroy
        render json: { notice: t("sources.destroy.notice") }
      end

      def refresh
        result = Sources::Actions.refresh(@source)
        return render_alert(result.message) unless result.ok?

        render json: { notice: result.message }
      end

      def refresh_all
        result = Sources::Actions.refresh_all(current_user)
        render json: { notice: result.message, count: result.count }
      end

      private

      def set_source
        @source = current_user.sources.find(params[:id])
      end

      def source_params
        params.require(:source).permit(*PERMITTED)
      end

      def source_json(source)
        Serializers.source(source, event_count: source.events.count)
      end
    end
  end
end
