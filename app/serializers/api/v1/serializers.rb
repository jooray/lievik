# frozen_string_literal: true

module Api
  module V1
    # The small representations of docs/API_V1.md. Plain Ruby, no gem.
    module Serializers
      module_function

      def iso(time) = Context.iso(time)

      def user(user)
        {
          id: user.id,
          npub: user.npub,
          pubkey_hex: user.pubkey_hex,
          display_name: user.display_name,
          username: user.username,
          about: user.about,
          picture_url: user.picture_url,
          settings: {
            locale: user.locale,
            rating_engine: user.rating_engine,
            event_link_template: user.event_link_template,
            naddr_link_template: user.naddr_link_template,
            profile_link_template: user.profile_link_template,
            system_prompt: user.system_prompt,
            default_content_style: user.default_content_style
          }
        }
      end

      def source(source, event_count: nil)
        {
          id: source.id,
          source_type: source.source_type,
          identifier: source.identifier,
          name: source.name,
          description: source.description,
          distance: source.distance,
          settings: {
            include_replies: source.settings_include_replies,
            include_reposts: source.settings_include_reposts,
            import_days: source.settings_import_days
          },
          event_count: event_count,
          created_at: iso(source.created_at),
          updated_at: iso(source.updated_at)
        }
      end

      def channel(channel, pending_count: nil)
        {
          id: channel.id,
          name: channel.name,
          description: channel.description,
          language: channel.language,
          prompt: channel.prompt,
          content_prompt: channel.content_prompt,
          content_language: channel.content_language,
          content_style: channel.content_style,
          settings: {
            relevance_threshold: channel.relevance_threshold.to_i,
            humanize_output: channel.humanize_output?
          },
          pending_count: pending_count,
          created_at: iso(channel.created_at),
          updated_at: iso(channel.updated_at)
        }
      end

      def channel_event(ce, channel_name: false)
        json = {
          id: ce.id,
          channel_id: ce.channel_id,
          event_id: ce.event_id,
          relevance_score: ce.relevance_score,
          relevance_reason: ce.relevance_reason,
          used: ce.used,
          used_at: iso(ce.used_at),
          updated_at: iso(ce.updated_at),
          engine: ce.rating_details.is_a?(Hash) ? ce.rating_details["engine"] : nil
        }
        json[:channel_name] = ce.channel&.name if channel_name
        json
      end

      def activity_log(log, dev_log_count: nil)
        {
          id: log.id,
          activity_type: log.activity_type,
          status: log.status,
          message: log.message,
          progress: log.progress_percentage,
          metadata: log.metadata || {},
          created_at: iso(log.created_at),
          updated_at: iso(log.updated_at),
          completed_at: iso(log.completed_at),
          dev_log_count: dev_log_count,
          stale: log.stale?
        }
      end

      def dev_log(log)
        { id: log.id, log_type: log.log_type, message: log.message, details: log.details || {}, created_at: iso(log.created_at) }
      end

      def channel_content(content, event_ids: nil)
        {
          id: content.id,
          channel_id: content.channel_id,
          title: content.title,
          content: content.content,
          generation_prompt: content.generation_prompt,
          status: content.status,
          published_at: iso(content.published_at),
          event_ids: event_ids || content.channel_content_events.map(&:event_id),
          versions_count: Array(content.version_history).size,
          created_at: iso(content.created_at),
          updated_at: iso(content.updated_at)
        }
      end

      def api_token(token, current: nil)
        {
          id: token.id,
          name: token.name,
          preview: token.masked_preview,
          created_at: iso(token.created_at),
          last_used_at: iso(token.last_used_at),
          expires_at: iso(token.expires_at),
          current: current ? token.id == current.id : false
        }
      end

      def billing_status(snapshot, user)
        others = NostrBilling::PRODUCTS.excluding(Billing::PRODUCT).filter_map do |product|
          next unless snapshot.active?(product) || snapshot.trial?(product)

          { product: product, state: snapshot.state(product), until: iso(snapshot.until_time(product)) }
        end

        {
          enabled: Billing.enabled?,
          state: snapshot.state,
          allows: snapshot.allows?,
          until: iso(snapshot.until_time),
          other_products: others,
          npub: user.npub
        }
      end

      def pagination(relation)
        {
          page: relation.current_page,
          per: relation.limit_value,
          total_pages: relation.total_pages,
          total_count: relation.total_count
        }
      end
    end
  end
end
