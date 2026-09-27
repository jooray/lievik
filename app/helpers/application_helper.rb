module ApplicationHelper
  # The `js.*` subtree for the current locale, English-backfilled so a key
  # missing from sk/cs/es still shows English rather than the raw key.
  # to_json escapes <, > and & as \u003c etc., so this is safe inside <script>.
  def js_translations
    english = I18n.t("js", locale: :en, default: {})
    return english if I18n.locale == :en

    english.deep_merge(I18n.t("js", default: {}))
  end

  # Language names in their own language, for switchers.
  LOCALE_NAMES = { en: "English", sk: "Slovenčina", cs: "Čeština", es: "Español" }.freeze

  def locale_options
    I18n.available_locales.map { |l| [LOCALE_NAMES.fetch(l, l.to_s), l.to_s] }
  end

  MARKDOWN_RENDERER = Redcarpet::Markdown.new(
    Redcarpet::Render::HTML.new(
      filter_html: true,
      hard_wrap: true,
      link_attributes: { rel: "noopener noreferrer", target: "_blank" }
    ),
    autolink: true,
    fenced_code_blocks: true,
    no_intra_emphasis: true,
    strikethrough: true,
    tables: true,
    underline: true
  )

  # ONE absolute date/time format for the whole app. Views used to carry five
  # different strftime strings; always go through this instead. The pattern
  # itself is per-locale: `time.formats.app_datetime` in config/locales/helpers/.
  APP_DATETIME_FORMAT = :app_datetime

  # Accepts a Time/DateTime/Date, or a string (e.g. a timestamp read back out of
  # a JSON column). Returns "" rather than blowing up on nil or garbage.
  def format_datetime(value)
    return "" if value.blank?

    time = case value
    when String then (Time.zone.parse(value) rescue nil)
    when Date then value.to_time
    else value
    end
    return "" if time.blank?

    l(time, format: APP_DATETIME_FORMAT)
  end

  # "3 hours ago" in the current locale. Never concatenate "ago" by hand:
  # Slovak/Czech/Spanish put the preposition first and inflect the noun.
  def time_ago(time)
    return "" if time.blank?

    t("app.time_ago", time: time_ago_in_words(time))
  end

  # Event#event_type is a code value (original/reply/repost); this is its label.
  def event_type_label(event_type)
    t("app.event_types.#{event_type}", default: event_type.to_s.humanize)
  end

  # Link target for the language switcher: the page being viewed, with
  # ?locale= set (switch_locale remembers it). Pages rendered from a POST
  # (e.g. a failed form) have no GET twin, so they fall back to the dashboard.
  def locale_switch_path(code)
    return dashboard_path(locale: code) unless request.get? || request.head?

    "#{request.path}?#{request.query_parameters.merge("locale" => code.to_s).to_query}"
  end

  # A source's display name is optional (and the auto-created "manual" source
  # has none), so never interpolate `source.name` straight into a view — that
  # renders a dangling "from ".
  def source_label(source)
    return t("app.source_label.unknown") if source.nil?
    return source.name if source.name.present?

    case source.source_type
    when "manual" then t("app.source_label.manual")
    else source.identifier.presence&.truncate(30) || t("app.source_label.unnamed")
    end
  end

  def relevance_score_class(score)
    case score
    when 80..100 then "bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200"
    when 50..79 then "bg-yellow-100 text-yellow-800 dark:bg-yellow-900 dark:text-yellow-200"
    else "bg-gray-100 text-gray-800 dark:bg-gray-700 dark:text-gray-200"
    end
  end

  def top_relevant_channels(event, limit: 3)
    event.channel_events
      .select { |ce| !ce.used? }
      .sort_by { |ce| -(ce.relevance_score || 0) }
      .first(limit)
  end

  # Feed/relay-supplied URLs must never reach an href unfiltered — a
  # `javascript:` link would execute in-app when clicked. Returns nil if unsafe.
  def safe_external_url(url)
    return nil if url.blank?

    uri = URI.parse(url.to_s.strip)
    return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    return nil if uri.host.blank?

    uri.to_s
  rescue URI::InvalidURIError
    nil
  end

  # Host of an external URL, for labelling a link with the client it opens in
  # ("yakihonne.com", "primal.net", ...). The link template is user-supplied, so
  # it may not parse — fall back to a generic label at the call site.
  def external_host(url)
    safe = safe_external_url(url)
    return nil if safe.blank?

    URI.parse(safe).host&.sub(/\Awww\./, "")
  rescue URI::InvalidURIError
    nil
  end

  def render_markdown(content)
    return "" if content.blank?

    sanitize(
      MARKDOWN_RENDERER.render(content),
      tags: %w[p br h1 h2 h3 h4 h5 h6 ul ol li strong em a blockquote code pre hr],
      attributes: %w[href rel target]
    )
  end

  # The markdown editor is its own JS bundle, pulled in only by the ~4 pages
  # that have one (via content_for :head) instead of riding along in
  # application.js. Exactly one implementation is ever sent to the browser —
  # see User#markdown_editor and app/javascript/editor_*.js.
  def markdown_editor_tags
    editor = current_user&.markdown_editor || "overtype"

    tags = []
    # OverType generates its own CSS at runtime; only EasyMDE needs a stylesheet.
    tags << stylesheet_link_tag("easymde", "data-turbo-track": "reload") if editor == "easymde"
    tags << javascript_include_tag("editor_#{editor}", "data-turbo-track": "reload", type: "module")

    safe_join(tags, "\n")
  end
end
