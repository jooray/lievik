# frozen_string_literal: true

module Events
  # The "all events" list filter (source, type, text search), newest first.
  # Shared by the web events page, its bulk-rate button, and the app API, so
  # the count shown is the set that actually gets rated.
  module Filter
    PARAMS = %i[source_id event_type search].freeze

    def self.call(user, params)
      params = (params || {}).to_h.symbolize_keys
      scope = user.events.recent
      scope = scope.where(source_id: params[:source_id]) if params[:source_id].present?
      scope = scope.where(event_type: params[:event_type]) if params[:event_type].present?
      if params[:search].present?
        # Escape LIKE metacharacters, otherwise a search for "%" matches every row
        # and forces a full scan. "!" as the escape char behaves the same on
        # SQLite (dev) and MariaDB (production); "\" does not.
        pattern = ActiveRecord::Base.sanitize_sql_like(params[:search].to_s, "!")
        scope = scope.where("content LIKE ? ESCAPE '!'", "%#{pattern}%")
      end
      scope
    end

    # Sources for the filter dropdown. Named sources first; the unnamed
    # auto-created "manual" source is labelled by Source#display_label.
    def self.sources(user)
      user.sources.order(Arel.sql("CASE WHEN name IS NULL OR name = '' THEN 1 ELSE 0 END"), :name)
    end
  end
end
