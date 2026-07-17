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
      .sort_by { |ce| -ce.relevance_score }
      .first(limit)
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
