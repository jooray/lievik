# frozen_string_literal: true

module NostrContentHelper
  NOSTR_URI_PATTERN = Nostr::ReferenceResolver::PATTERN

  def render_nostr_content(content, user: current_user)
    return "" if content.blank?

    escaped = h(content)

    resolved = escaped.gsub(NOSTR_URI_PATTERN) do |match|
      identifier = match.sub(/\Anostr:/i, "")
      resolve_nostr_reference(identifier, user)
    end

    resolved.html_safe
  end

  # Short/collapsed previews must resolve `nostr:` references BEFORE truncating.
  # Truncating first cuts bech32 identifiers mid-string, and the leftover stub
  # no longer matches NOSTR_URI_PATTERN — so a raw "nostr:nevent1qq…" leaks into
  # the card. Event#content_for_embedding does the resolution to plain text.
  def nostr_content_preview(event, length:)
    text = event.respond_to?(:content_for_embedding) ? event.content_for_embedding : event.to_s
    h(truncate(text.to_s, length: length))
  end

  private

  # Per-request memoization: the same npub/note is typically referenced by many
  # cards on one page. The view context object lives for the whole request (and
  # is shared across partials), so an ivar here is request-local.
  def nostr_reference_cache
    @_nostr_reference_cache ||= {}
  end

  # One resolver per user per request (it memoizes the lookups themselves).
  def nostr_reference_resolver(user)
    @_nostr_reference_resolvers ||= {}
    @_nostr_reference_resolvers[user&.id] ||= Nostr::ReferenceResolver.new(user)
  end

  def resolve_nostr_reference(identifier, user)
    cache_key = [identifier, user&.id]
    cache = nostr_reference_cache
    return cache[cache_key] if cache.key?(cache_key)

    cache[cache_key] = render_nostr_reference(identifier, nostr_reference_resolver(user).resolve(identifier))
  end

  # HTML for one resolved reference (see Nostr::ReferenceResolver#resolve).
  def render_nostr_reference(identifier, ref)
    case ref&.dig(:type)
    when :profile
      label = ref[:display_name].present? ? "@#{ref[:display_name]}" : "@#{ref[:npub]&.truncate(20)}"
      link_to(label, ref[:url], target: "_blank", rel: "noopener noreferrer",
              class: "text-purple-600 dark:text-purple-400 hover:underline font-medium",
              title: ref[:npub])
    when :event
      if ref[:resolved]
        render_inline_note_card(ref[:content], ref[:author_name], ref[:url], identifier)
      else
        link_to(t("app.nostr.referenced_note"), ref[:url], target: "_blank", rel: "noopener noreferrer",
                class: "text-purple-600 dark:text-purple-400 hover:underline",
                title: identifier)
      end
    when :article
      label = ref[:slug].present? ? ref[:slug].truncate(40) : identifier.truncate(20)
      link_to(label, ref[:url], target: "_blank", rel: "noopener noreferrer",
              class: "text-purple-600 dark:text-purple-400 hover:underline",
              title: identifier)
    else
      "nostr:#{identifier}"
    end
  end

  def render_inline_note_card(content, author_name, url, identifier)
    author_label = author_name.present? ? h(author_name) : h(t("app.nostr.unknown_author"))
    truncated_content = h(content.truncate(300))

    <<~HTML
      <a href="#{h(url)}" target="_blank" rel="noopener noreferrer" title="#{h(identifier)}"
         class="block border border-gray-200 dark:border-gray-600 rounded-lg p-3 my-2 bg-gray-50 dark:bg-gray-700 hover:bg-gray-100 dark:hover:bg-gray-600 transition-colors no-underline cursor-pointer">
        <span class="text-xs font-medium text-purple-600 dark:text-purple-400">#{author_label}</span>
        <span class="block text-sm text-gray-700 dark:text-gray-200 mt-1 whitespace-pre-wrap">#{truncated_content}</span>
      </a>
    HTML
  end
end
