module ApplicationHelper
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
  # different strftime strings; always go through this instead.
  APP_DATETIME_FORMAT = "%b %d, %Y at %H:%M"

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

    time.strftime(APP_DATETIME_FORMAT)
  end

  # A source's display name is optional (and the auto-created "manual" source
  # has none), so never interpolate `source.name` straight into a view — that
  # renders a dangling "from ".
  def source_label(source)
    return "Unknown source" if source.nil?
    return source.name if source.name.present?

    case source.source_type
    when "manual" then "Manual entries"
    else source.identifier.presence&.truncate(30) || "Unnamed source"
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

  def render_markdown(content)
    return "" if content.blank?

    sanitize(
      MARKDOWN_RENDERER.render(content),
      tags: %w[p br h1 h2 h3 h4 h5 h6 ul ol li strong em a blockquote code pre hr],
      attributes: %w[href rel target]
    )
  end
end
