# frozen_string_literal: true

module Api
  module V1
    class ChannelsController < BaseController
      before_action :set_channel, only: [ :show, :update, :destroy, :rate ]
      requires_paid_access only: :rate

      def index
        channels = current_user.channels.order(:name).to_a
        pending = Channels::PendingCounts.for(channels)
        render json: { channels: channels.map { |c| Serializers.channel(c, pending_count: pending[c.id] || 0) } }
      end

      def show
        counts = ChannelEvents::Listing.new(@channel).counts
        render json: {
          channel: channel_json(@channel),
          used_count: counts[:used],
          unused_count: counts[:unused],
          default_prompt_template: Channel.default_prompt_template
        }
      end

      # The defaults the web's new-channel form starts from.
      def new
        channel = current_user.channels.build(prompt: Channel.default_prompt_template, content_style: current_user.default_content_style)
        render json: { channel: Serializers.channel(channel).except(:id, :pending_count, :created_at, :updated_at) }
      end

      def create
        channel = current_user.channels.build(params.require(:channel).permit(:name, :description, :language, :prompt))
        return render_invalid(channel) unless channel.save

        queued = Channels::InitialRating.queue(channel)
        render json: { channel: channel_json(channel), notice: Channels::InitialRating.created_notice(queued), queued: queued },
               status: :created
      end

      # The web's edit form and settings form in one. `settings` is merged
      # into the existing settings, so a partial update keeps the rest.
      def update
        attributes = params.require(:channel).permit(:name, :description, :language, :prompt,
                                                     :content_prompt, :content_language, :content_style,
                                                     settings: [ :relevance_threshold, :humanize_output ]).to_h
        if attributes.key?("settings")
          attributes["settings"] = (@channel.settings || {}).merge(attributes["settings"].to_h.stringify_keys)
        end
        return render_invalid(@channel) unless @channel.update(attributes)

        render json: { channel: channel_json(@channel), notice: t("channels.update.notice") }
      end

      def destroy
        @channel.destroy
        render json: { notice: t("channels.destroy.notice") }
      end

      def rate
        @channel.rate_new_events!
        render json: { notice: t("channels.rate.notice") }
      end

      private

      def set_channel
        @channel = current_user.channels.find(params[:id])
      end

      def channel_json(channel)
        Serializers.channel(channel, pending_count: Channels::PendingCounts.for([ channel ])[channel.id] || 0)
      end
    end
  end
end
