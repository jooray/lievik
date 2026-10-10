# frozen_string_literal: true

module Sources
  # What happens after a source is added, and the refresh buttons. Shared by
  # SourcesController and the app API so trial start, job queueing and the
  # notice text stay identical.
  module Actions
    Result = Struct.new(:ok, :message, :importing, :count, keyword_init: true) do
      def ok? = ok
    end

    # Without this the dashboard stays empty until the user discovers the
    # small refresh icon — the first-run flow reads as broken. Adding a source
    # is an explicit request for data, so it starts the trial; the source is
    # kept either way.
    def self.after_create(source, user)
      fetchable = source.nostr? || source.rss?
      if fetchable && Billing.activate(user).allows?
        SourceIngestionJob.perform_later(source.id)
        Result.new(ok: true, importing: true, message: I18n.t("sources.create.importing"))
      elsif fetchable
        Result.new(ok: true, importing: false, message: I18n.t("billing.source_saved_paused"))
      else
        Result.new(ok: true, importing: false, message: I18n.t("sources.create.notice"))
      end
    end

    # Callers gate this with requires_paid_access.
    def self.refresh(source)
      return Result.new(ok: false, message: I18n.t("sources.refresh.unsupported")) unless source.nostr? || source.rss?

      SourceIngestionJob.perform_later(source.id)
      message = source.name.present? ? I18n.t("sources.refresh.notice", name: source.name) : I18n.t("sources.refresh.notice_unnamed")
      Result.new(ok: true, message: message)
    end

    # Callers gate this with requires_paid_access.
    def self.refresh_all(user)
      sources = user.sources.where(source_type: [ :nostr, :rss ])
      sources.find_each { |source| SourceIngestionJob.perform_later(source.id) }
      count = sources.count
      Result.new(ok: true, count: count, message: I18n.t("sources.refresh_all.notice", count: count))
    end
  end
end
