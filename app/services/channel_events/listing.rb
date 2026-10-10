# frozen_string_literal: true

module ChannelEvents
  # The curation queue of one channel: events above the channel's threshold,
  # unused only unless `show_used`, optionally searched, in one of the
  # whitelisted sort orders, plus the used/unused counts. The web channel page
  # and the app API both list through this, so they always agree.
  class Listing
    # Whitelist: the value picks an ORDER BY, so it must never come straight
    # from params. "relevance" is the default.
    SORT_OPTIONS = %w[relevance newest oldest].freeze
    DEFAULT_SORT = "relevance"

    attr_reader :channel, :threshold, :show_used, :search, :sort

    def self.normalize_sort(value)
      SORT_OPTIONS.include?(value) ? value : DEFAULT_SORT
    end

    def initialize(channel, show_used: false, search: nil, sort: nil)
      @channel = channel
      @threshold = channel.relevance_threshold
      @show_used = show_used
      @search = search
      @sort = self.class.normalize_sort(sort)
    end

    # Unpaginated, ordered relation (call .page/.per on it).
    def scope
      scope = channel.channel_events
        .includes(event: :source)
        .above_threshold(threshold)

      if search.present?
        # Escape LIKE metacharacters — an unescaped "%" would match every row.
        # "!" as the escape char behaves the same on SQLite and MariaDB.
        pattern = ActiveRecord::Base.sanitize_sql_like(search.to_s, "!")
        scope = scope.joins(:event).where("events.content LIKE ? ESCAPE '!'", "%#{pattern}%")
      end

      # The chosen sort applies within each group — used events stay pinned
      # to the bottom regardless of it.
      scope = show_used ? scope.order(used: :asc) : scope.unused

      case sort
      when "newest" then scope.by_newest
      when "oldest" then scope.by_oldest
      else scope.by_relevance
      end
    end

    # { used:, unused: } above the threshold. One grouped query instead of two
    # COUNTs. `used` is a boolean, so the keys come back as true/false (SQLite
    # returns 0/1, hence the coercion).
    def counts
      @counts ||= begin
        result = { used: 0, unused: 0 }
        channel.channel_events.above_threshold(threshold).group(:used).count.each do |used, count|
          ActiveModel::Type::Boolean.new.cast(used) ? result[:used] += count : result[:unused] += count
        end
        result
      end
    end
  end
end
