# frozen_string_literal: true

module Api
  module V1
    # The content builder: drafts, AI generation/refinement over SSE, publish
    # and revert. Generation goes through ChannelContents::Generation, the
    # same code the web streams through.
    class ChannelContentsController < BaseController
      include ActionController::Live
      include SseStreaming

      before_action :set_channel
      before_action :set_channel_content, except: [ :index, :create ]
      # After set_channel_content, so a 404 wins and a denied generation saves
      # no version.
      requires_paid_ai kind: "content", only: :generate
      requires_paid_ai kind: "content", prompt: :user_prompt, only: :refine

      def index
        contents = @channel.channel_contents.includes(:channel_content_events)
        render json: {
          drafts: contents.drafts.map { |c| Serializers.channel_content(c) },
          published: contents.published_content.map { |c| Serializers.channel_content(c) }
        }
      end

      def show
        events = @channel_content.events.includes(:source, channel_events: :channel)
        render json: { content: content_json, events: EventSerializer.many(events, serialization_context) }
      end

      def create
        @channel_content = ChannelContents::Editor.create(@channel, current_user, content_params, params[:event_ids])
        return render_invalid(@channel_content) unless @channel_content.persisted?

        render json: { content: content_json, notice: t("channel_contents.create.notice") }, status: :created
      end

      def update
        return render_invalid(@channel_content) unless ChannelContents::Editor.update(@channel_content, content_params)

        render json: { content: content_json, notice: t("channel_contents.update.notice") }
      end

      def destroy
        @channel_content.destroy
        render json: { notice: t("channel_contents.destroy.notice") }
      end

      def generate
        stream_sse { |sse| ChannelContents::Generation.new(@channel_content, current_user).generate(sse) }
      end

      def refine
        stream_sse { |sse| ChannelContents::Generation.new(@channel_content, current_user).refine(sse, params[:user_prompt]) }
      end

      def publish
        @channel_content.publish!
        render json: { content: content_json, notice: t("channel_contents.publish.notice") }
      end

      def revert
        unless @channel_content.revert_to_previous!
          return render_error(:unprocessable_content, "no_previous", t("channel_contents.revert.no_previous"))
        end

        render json: { content: content_json, notice: t("channel_contents.revert.notice") }
      end

      private

      def set_channel
        @channel = current_user.channels.find(params[:channel_id])
      end

      def set_channel_content
        @channel_content = @channel.channel_contents.find(params[:id])
      end

      def content_params
        params.require(:channel_content).permit(:title, :content, :generation_prompt)
      end

      def content_json
        Serializers.channel_content(@channel_content.reload, event_ids: @channel_content.channel_content_events.pluck(:event_id))
      end
    end
  end
end
