#!/usr/bin/env ruby
# frozen_string_literal: true

# Generates the app's string resources in all four languages.
#
#   ruby android/tools/strings/generate.rb
#
# * strings_web.xml — wording taken verbatim from the web's locale files
#   (config/locales/**/{en,sk,cs,es}.yml) through the WEB map below, so the app
#   and the web read the same. Rails' %{name} placeholders become positional
#   Android ones in the order they first appear in the English text (%{count}
#   becomes %N$d, everything else %N$s).
# * strings_app.xml — strings only the app needs, from app_strings.yml
#   (already in Android format).
#
# The output is committed, so building the app never needs Ruby. Re-run after
# changing either input. Fails loudly when a key or a translation is missing.

require "yaml"
require "cgi"

ROOT = File.expand_path("../../..", __dir__)
RES = File.join(ROOT, "android/app/src/main/res")
LANGS = %w[en sk cs es].freeze
# Android plural categories to emit. sk/cs "many" is the decimal form; es
# "many" is the millions form in newer CLDR. Both fall back to "other".
QUANTITIES = { "en" => %w[one other], "sk" => %w[one few many other], "cs" => %w[one few many other], "es" => %w[one many other] }.freeze

WEB = {
  # common
  "common_cancel" => "common.cancel", "common_save" => "common.save", "common_edit" => "common.edit",
  "common_delete" => "common.delete", "common_back" => "common.back", "common_add" => "common.add",
  "common_close" => "common.close", "common_language" => "common.language", "common_confirm_delete" => "common.confirm_delete",
  "common_copy" => "js.common.copy", "common_copied" => "js.common.copied", "common_loading" => "js.common.loading",
  "show_more" => "js.event_expander.show_more", "show_less" => "js.event_expander.show_less",

  # navigation
  "nav_dashboard" => "layouts.navigation.dashboard", "nav_sources" => "layouts.navigation.sources",
  "nav_channels" => "layouts.navigation.channels", "nav_events" => "layouts.navigation.events",
  "nav_add_event" => "layouts.navigation.add_event", "nav_activity" => "layouts.navigation.activity",
  "nav_ask_content" => "layouts.navigation.ask_content", "nav_profile" => "layouts.navigation.profile",
  "nav_nostr_user" => "layouts.navigation.nostr_user", "nav_refresh_profile" => "layouts.navigation.refresh_profile",
  "nav_sign_out" => "layouts.navigation.sign_out", "nav_billing" => "billing.nav",

  # helpers
  "event_type_original" => "app.event_types.original", "event_type_reply" => "app.event_types.reply",
  "event_type_repost" => "app.event_types.repost",
  "source_label_unknown" => "app.source_label.unknown", "source_label_manual" => "app.source_label.manual",
  "source_label_unnamed" => "app.source_label.unnamed",
  "nostr_referenced_note" => "app.nostr.referenced_note", "nostr_unknown_author" => "app.nostr.unknown_author",

  # sessions (login)
  "login_subtitle" => "sessions.new.subtitle", "login_signer_heading" => "sessions.new.signer_heading",
  "login_open_in_signer" => "sessions.new.open_in_signer", "login_signer_hint" => "sessions.new.signer_hint",
  "login_scan_hint" => "sessions.new.scan_hint", "login_bunker_heading" => "sessions.new.bunker_heading",
  "login_bunker_hint" => "sessions.new.bunker_hint", "login_bunker_label" => "sessions.new.bunker_label",
  "login_connect" => "sessions.new.connect", "login_waiting" => "sessions.new.waiting",
  "login_stale_notice" => "sessions.new.stale_notice", "login_new_code" => "sessions.new.new_code",
  "login_auth_challenge" => "sessions.new.auth_challenge", "login_open_approval" => "sessions.new.open_approval",
  "login_expired" => "sessions.new.expired", "login_no_account" => "sessions.new.no_account",
  "login_try_again" => "sessions.unavailable.try_again",
  "login_busy_title" => "sessions.unavailable_reasons.busy.title", "login_busy_message" => "sessions.unavailable_reasons.busy.message",
  "login_rate_limited_title" => "sessions.unavailable_reasons.rate_limited.title",
  "login_rate_limited_message" => "sessions.unavailable_reasons.rate_limited.message",
  "login_bunker_invalid" => "sessions.bunker.invalid_link", "login_bunker_failed" => "sessions.bunker.failed",
  "login_failed" => "sessions.callback.failed", "login_welcome" => "sessions.callback.welcome",
  "login_paste_bunker_first" => "js.nostr_login.paste_bunker_first", "login_connecting" => "js.nostr_login.connecting",
  "login_waiting_approval" => "js.nostr_login.waiting_approval", "error_network" => "js.nostr_login.server_unreachable",
  "error_unknown" => "js.nostr_login.unknown_error",

  # billing
  "billing_start_trial" => "billing.start_trial", "billing_denied" => "billing.denied",
  "billing_paywall" => "billing.paywall", "billing_daily_cap" => "billing.daily_cap",
  "billing_unavailable" => "billing.unavailable", "billing_paid" => "billing.paid",
  "billing_banner_none" => "billing.banner.none", "billing_banner_trial" => "billing.banner.trial",
  "billing_banner_expired" => "billing.banner.expired", "billing_banner_plans" => "billing.banner.plans",
  "billing_sats_range" => "billing.errors.sats_range", "billing_title" => "billing.show.title",
  "billing_intro" => "billing.show.intro", "billing_status_title" => "billing.show.status.title",
  "billing_status_active" => "billing.show.status.active", "billing_status_trial" => "billing.show.status.trial",
  "billing_status_expired" => "billing.show.status.expired", "billing_status_none" => "billing.show.status.none",
  "billing_status_unknown" => "billing.show.status.unknown", "billing_status_other" => "billing.show.status.other",
  "billing_status_npub" => "billing.show.status.npub",
  "billing_product_nalgorithm" => "billing.show.products.nalgorithm", "billing_product_emanator_ai" => "billing.show.products.emanator_ai",
  "billing_product_lievik" => "billing.show.products.lievik",
  "billing_plan_price" => "billing.show.plans.price", "billing_plan_pay" => "billing.show.plans.pay",
  "billing_plans_unavailable" => "billing.show.plans.unavailable",
  "billing_plan_lievik_name" => "billing.show.plans.lievik.name", "billing_plan_lievik_covers" => "billing.show.plans.lievik.covers",
  "billing_plan_all_access_name" => "billing.show.plans.all_access.name",
  "billing_plan_all_access_covers" => "billing.show.plans.all_access.covers",
  "billing_custom_title" => "billing.show.custom.title", "billing_custom_help" => "billing.show.custom.help",
  "billing_custom_plan" => "billing.show.custom.plan", "billing_custom_sats" => "billing.show.custom.sats",
  "billing_custom_pay" => "billing.show.custom.pay", "billing_self_host" => "billing.show.self_host_html",
  "billing_see_plans" => "js.billing.open_plans",

  # dashboard
  "dashboard_title" => "dashboard.index.title", "dashboard_welcome_back" => "dashboard.index.welcome_back",
  "dashboard_rate_all_unrated" => "dashboard.index.rate_all_unrated", "dashboard_sources" => "dashboard.index.sources",
  "dashboard_channels" => "dashboard.index.channels", "dashboard_events" => "dashboard.index.events",
  "dashboard_ask_content" => "dashboard.index.ask_content", "dashboard_indexed" => "dashboard.index.indexed",
  "dashboard_view_all" => "dashboard.index.view_all", "dashboard_view_all_events" => "dashboard.index.view_all_events",
  "dashboard_jobs_running" => "dashboard.index.jobs_running", "dashboard_step1_title" => "dashboard.index.step1_title",
  "dashboard_step1_body" => "dashboard.index.step1_body", "dashboard_add_source" => "dashboard.index.add_source",
  "dashboard_step2_title" => "dashboard.index.step2_title", "dashboard_step2_body" => "dashboard.index.step2_body",
  "dashboard_create_channel" => "dashboard.index.create_channel", "dashboard_describe_to_ai" => "dashboard.index.describe_to_ai",
  "dashboard_recent_events" => "dashboard.index.recent_events", "dashboard_no_events_title" => "dashboard.index.no_events_title",
  "dashboard_no_events_body" => "dashboard.index.no_events_body", "dashboard_refresh_all_sources" => "dashboard.index.refresh_all_sources",
  "dashboard_manage_sources" => "dashboard.index.manage_sources", "dashboard_add_manually" => "dashboard.index.add_manually",

  # sources
  "source_attr_identifier" => "activerecord.attributes.source.identifier", "source_attr_name" => "activerecord.attributes.source.name",
  "source_attr_description" => "activerecord.attributes.source.description",
  "sources_title" => "sources.index.title", "sources_subtitle" => "sources.index.subtitle",
  "sources_refresh_all" => "sources.index.refresh_all", "sources_add_source" => "sources.index.add_source",
  "sources_empty_title" => "sources.index.empty_title", "sources_empty_hint" => "sources.index.empty_hint",
  "sources_distance" => "sources.index.distance", "sources_events" => "sources.index.events",
  "sources_view_profile" => "sources.index.view_profile", "sources_click_to_copy" => "sources.index.click_to_copy",
  "source_new_title" => "sources.new.title", "source_new_subtitle" => "sources.new.subtitle",
  "source_edit_title" => "sources.edit.title", "source_danger_zone" => "sources.edit.danger_zone",
  "source_danger_hint" => "sources.edit.danger_hint", "source_confirm_delete" => "sources.edit.confirm_delete",
  "source_delete" => "sources.edit.delete", "source_removed" => "sources.destroy.notice",
  "channel_deleted" => "channels.destroy.notice", "content_deleted" => "channel_contents.destroy.notice",
  "token_revoked" => "api_tokens.destroy.notice", "template_deleted" => "users.delete_template.notice",
  "source_type_nostr" => "sources.show.source_type.nostr", "source_type_rss" => "sources.show.source_type.rss",
  "source_type_manual" => "sources.show.source_type.manual", "source_show_events" => "sources.show.events",
  "source_show_empty" => "sources.show.empty",
  "source_form_type" => "sources.form.source_type", "source_form_type_nostr" => "sources.form.types.nostr",
  "source_form_type_rss" => "sources.form.types.rss", "source_form_name_placeholder" => "sources.form.name_placeholder",
  "source_form_name_hint" => "sources.form.name_hint", "source_form_description_placeholder" => "sources.form.description_placeholder",
  "source_form_distance" => "sources.form.distance", "source_form_distance_hint" => "sources.form.distance_hint",
  "source_form_import_settings" => "sources.form.import_settings", "source_form_include_replies" => "sources.form.include_replies",
  "source_form_include_reposts" => "sources.form.include_reposts", "source_form_import_days" => "sources.form.import_days",
  "source_form_import_days_hint" => "sources.form.import_days_hint", "source_form_create" => "sources.form.create",
  "source_form_update" => "sources.form.update",
  "source_form_nostr_label" => "js.source_form.nostr_label", "source_form_rss_label" => "js.source_form.rss_label",
  "source_form_nostr_hint" => "js.source_form.nostr_hint", "source_form_rss_hint" => "js.source_form.rss_hint",
  "source_invalid_npub" => "activerecord.errors.models.source.attributes.identifier.invalid_npub",

  # channels
  "channel_attr_name" => "activerecord.attributes.channel.name", "channel_attr_description" => "activerecord.attributes.channel.description",
  "channel_attr_language" => "activerecord.attributes.channel.language",
  "channels_title" => "channels.index.title", "channels_subtitle" => "channels.index.subtitle",
  "channels_create_with_ai" => "channels.index.create_with_ai", "channels_create_channel" => "channels.index.create_channel",
  "channels_empty_title" => "channels.index.empty_title", "channels_empty_body" => "channels.index.empty_body",
  "channels_pending" => "channels.index.pending",
  "channel_new_title" => "channels.new.title", "channel_new_subtitle" => "channels.new.subtitle",
  "channel_edit_title" => "channels.edit.title", "channel_edit_subtitle" => "channels.edit.subtitle",
  "channel_form_name_placeholder" => "channels.form.name_placeholder",
  "channel_form_description_placeholder" => "channels.form.description_placeholder",
  "channel_form_language_hint" => "channels.form.language_hint", "channel_form_criteria_label" => "channels.form.criteria_label",
  "channel_form_criteria_hint" => "channels.form.criteria_hint", "channel_form_create" => "channels.form.create",
  "channel_form_update" => "channels.form.update",
  "channel_content_library" => "channels.show.content_library", "channel_settings" => "channels.show.settings",
  "channel_edit_criteria" => "channels.show.edit_criteria", "channel_relevant_content" => "channels.show.relevant_content",
  "channel_unused_count" => "channels.show.unused_count", "channel_used_count" => "channels.show.used_count",
  "channel_sort_label" => "channels.show.sort_label", "channel_sort_relevance" => "channels.show.sort_relevance",
  "channel_sort_newest" => "channels.show.sort_newest", "channel_sort_oldest" => "channels.show.sort_oldest",
  "channel_threshold" => "channels.show.threshold", "channel_show_used" => "channels.show.show_used",
  "channel_select_all_page" => "channels.show.select_all_page", "channel_selected_count" => "channels.show.selected_count",
  "channel_search_placeholder" => "channels.show.search_placeholder", "channel_search" => "channels.show.search",
  "channel_clear" => "channels.show.clear", "channel_use_events" => "channels.show.use_events",
  "channel_mark_used" => "channels.show.mark_used", "channel_rate_events" => "channels.show.rate_events",
  "channel_empty" => "channels.show.empty", "channel_ai_reasoning" => "channels.show.ai_reasoning",
  "channel_used" => "channels.show.used", "channel_from_source" => "channels.show.from_source",
  "channel_view_details" => "channels.show.view_details",
  "channel_settings_title" => "channels.settings.title", "channel_threshold_label" => "channels.settings.threshold_label",
  "channel_threshold_hint" => "channels.settings.threshold_hint", "channel_show_everything" => "channels.settings.show_everything",
  "channel_only_high" => "channels.settings.only_high", "channel_generation_heading" => "channels.settings.generation_heading",
  "channel_generation_hint" => "channels.settings.generation_hint", "channel_content_language" => "channels.settings.content_language",
  "channel_content_language_hint" => "channels.settings.content_language_hint",
  "channel_content_language_placeholder" => "channels.settings.content_language_placeholder",
  "channel_writing_style" => "channels.settings.writing_style", "channel_writing_style_hint" => "channels.settings.writing_style_hint",
  "channel_writing_style_placeholder" => "channels.settings.writing_style_placeholder",
  "channel_humanize" => "channels.settings.humanize", "channel_humanize_hint" => "channels.settings.humanize_hint",
  "channel_formatting" => "channels.settings.formatting", "channel_formatting_hint" => "channels.settings.formatting_hint",
  "channel_load_from_template" => "channels.settings.load_from_template",
  "channel_manage_templates" => "channels.settings.manage_templates",
  "channel_create_templates_hint" => "channels.settings.create_templates_hint", "channel_settings_save" => "channels.settings.save",
  "channel_danger_zone" => "channels.settings.danger_zone", "channel_danger_body" => "channels.settings.danger_body",
  "channel_delete" => "channels.settings.delete", "channel_delete_confirm" => "channels.settings.delete_confirm",
  "bulk_rerate_n" => "js.bulk_select.rerate_n", "bulk_mark_n" => "js.bulk_select.mark_n", "bulk_use_n" => "js.bulk_select.use_n",
  "channel_events_no_selection" => "channel_events.no_selection",
  "template_replace_confirm" => "js.template_selector.replace_confirm",

  # languages (the AI chat's longer list)
  "lang_en" => "js.channel_ai_chat.languages.en", "lang_sk" => "js.channel_ai_chat.languages.sk",
  "lang_cs" => "js.channel_ai_chat.languages.cs", "lang_de" => "js.channel_ai_chat.languages.de",
  "lang_es" => "js.channel_ai_chat.languages.es", "lang_fr" => "js.channel_ai_chat.languages.fr",
  "lang_pt" => "js.channel_ai_chat.languages.pt", "lang_it" => "js.channel_ai_chat.languages.it",
  "lang_pl" => "js.channel_ai_chat.languages.pl", "lang_uk" => "js.channel_ai_chat.languages.uk",
  "lang_nl" => "js.channel_ai_chat.languages.nl", "lang_hu" => "js.channel_ai_chat.languages.hu",

  # content builder
  "content_status_draft" => "channel_contents.statuses.draft", "content_status_published" => "channel_contents.statuses.published",
  "content_instructions_required" => "channel_contents.errors.instructions_required",
  "content_index_heading" => "channel_contents.index.heading", "content_index_subtitle" => "channel_contents.index.subtitle",
  "content_drafts" => "channel_contents.index.drafts", "content_untitled_draft" => "channel_contents.index.untitled_draft",
  "content_untitled" => "channel_contents.index.untitled", "content_source_events" => "channel_contents.index.source_events",
  "content_published_heading" => "channel_contents.index.published_heading", "content_empty" => "channel_contents.index.empty",
  "content_empty_hint" => "channel_contents.index.empty_hint",
  "content_versions_saved" => "channel_contents.content_status.versions_saved",
  "content_title_label" => "channel_contents.editor_container.title_label",
  "content_title_placeholder" => "channel_contents.editor_container.title_placeholder",
  "content_editor_placeholder" => "channel_contents.editor_container.content_placeholder",
  "content_save_draft" => "channel_contents.editor_container.save_draft",
  "content_please_wait" => "channel_contents.editor_streaming.please_wait",
  "content_waiting" => "channel_contents.editor_streaming.waiting",
  "content_direction_heading" => "channel_contents.generation_prompt_panel.heading",
  "content_direction_empty" => "channel_contents.generation_prompt_panel.empty",
  "content_direction_panel_placeholder" => "channel_contents.generation_prompt_panel.placeholder",
  "content_new_heading" => "channel_contents.new.heading", "content_new_subtitle" => "channel_contents.new.subtitle",
  "content_new_no_events" => "channel_contents.new.no_events", "content_new_title_placeholder" => "channel_contents.new.title_placeholder",
  "content_new_direction_label" => "channel_contents.new.direction_label",
  "content_new_direction_placeholder" => "channel_contents.new.direction_placeholder",
  "content_new_direction_hint" => "channel_contents.new.direction_hint",
  "content_new_selected_events" => "channel_contents.new.selected_events", "content_new_submit" => "channel_contents.new.submit",
  "content_edit_default_title" => "channel_contents.edit.default_title", "content_publish" => "channel_contents.edit.publish",
  "content_publish_confirm" => "channel_contents.edit.publish_confirm", "content_editor" => "channel_contents.edit.content_editor",
  "content_generate" => "channel_contents.edit.generate", "content_regenerate" => "channel_contents.edit.regenerate",
  "content_ai_edit" => "channel_contents.edit.ai_edit", "content_ai_edit_hint" => "channel_contents.edit.ai_edit_hint",
  "content_refine_placeholder" => "channel_contents.edit.refine_placeholder", "content_apply_ai_edit" => "channel_contents.edit.apply_ai_edit",
  "content_source_events_heading" => "channel_contents.edit.source_events", "content_events_used" => "channel_contents.edit.events_used",
  "content_version_history" => "channel_contents.edit.version_history",
  "content_previous_versions" => "channel_contents.edit.previous_versions",
  "content_restore_previous" => "channel_contents.edit.restore_previous", "content_restoring" => "channel_contents.edit.restoring",
  "content_restore_confirm" => "channel_contents.edit.restore_confirm",
  "content_published_default_title" => "channel_contents.show.default_title",
  "content_delete_confirm" => "channel_contents.show.delete_confirm", "content_copy_markdown" => "channel_contents.show.copy_markdown",
  "builder_connecting" => "js.content_builder.connecting", "builder_appears_below" => "js.content_builder.appears_below",
  "builder_generating" => "js.content_builder.generating", "builder_humanizing" => "js.content_builder.humanizing",
  "builder_generation_complete" => "js.content_builder.generation_complete", "builder_applying" => "js.content_builder.applying",
  "builder_refining" => "js.content_builder.refining", "builder_refinement_complete" => "js.content_builder.refinement_complete",
  "builder_instructions_required" => "js.content_builder.instructions_required",
  "builder_generic_error" => "js.content_builder.generic_error", "builder_error" => "js.content_builder.error",
  "builder_connection_error" => "js.content_builder.connection_error", "builder_connection_lost" => "js.content_builder.connection_lost",
  "builder_save_changes" => "js.content_editor.save_changes",

  # events
  "events_from_source" => "events.from_source", "events_view_details" => "events.view_details",
  "events_rerate_one_confirm" => "events.rerate_one_confirm", "events_selected" => "events.selected",
  "events_title" => "events.index.title", "events_subtitle" => "events.index.subtitle",
  "events_search" => "events.index.search", "events_search_placeholder" => "events.index.search_placeholder",
  "events_source" => "events.index.source", "events_all_sources" => "events.index.all_sources",
  "events_type" => "events.index.type", "events_all_types" => "events.index.all_types",
  "events_filter" => "events.index.filter", "events_clear" => "events.index.clear",
  "events_select_all_page" => "events.index.select_all_page", "events_rerate_confirm" => "events.index.rerate_confirm",
  "events_rerate_all" => "events.index.rerate_all", "events_rerate_one" => "events.index.rerate_one",
  "events_empty_title" => "events.index.empty_title", "events_empty_body" => "events.index.empty_body",
  "event_title" => "events.show.title", "event_back" => "events.show.back", "event_view_original" => "events.show.view_original",
  "event_rerate" => "events.show.rerate_event", "event_channel_relevance" => "events.show.channel_relevance",
  "event_select_all" => "events.show.select_all", "event_already_used" => "events.show.already_used",
  "event_mark_used_selected" => "events.show.mark_used_selected", "event_not_rated" => "events.show.not_rated",
  "event_rate_all_channels" => "events.show.rate_all_channels",
  "event_no_channels_selected" => "events.bulk_mark_used.no_channels_selected",

  # manual events
  "manual_title" => "manual_events.new.title", "manual_subtitle" => "manual_events.new.subtitle",
  "manual_content" => "manual_events.new.content", "manual_placeholder" => "manual_events.new.placeholder",
  "manual_submit" => "manual_events.new.submit",

  # ask (RAG chat)
  "rag_heading" => "rag_chat.index.heading", "rag_intro" => "rag_chat.index.intro",
  "rag_indexed" => "rag_chat.index.indexed_html", "rag_clear_chat" => "rag_chat.index.clear_chat",
  "rag_empty_title" => "rag_chat.index.empty_title", "rag_welcome" => "rag_chat.index.welcome",
  "rag_example_topics" => "rag_chat.index.example_topics", "rag_example_summary" => "rag_chat.index.example_summary",
  "rag_example_person" => "rag_chat.index.example_person", "rag_placeholder" => "rag_chat.index.placeholder",
  "rag_question_required" => "rag_chat.errors.question_required",
  "rag_thinking" => "js.rag_chat.thinking", "rag_sources" => "js.rag_chat.sources", "rag_view" => "js.rag_chat.view",
  "rag_generic_error" => "js.rag_chat.generic_error", "rag_failed_to_connect" => "js.rag_chat.failed_to_connect",

  # AI add channels
  "ai_title" => "channel_ai_chat.index.title", "ai_subtitle" => "channel_ai_chat.index.subtitle",
  "ai_existing" => "channel_ai_chat.index.existing_html", "ai_clear_chat" => "channel_ai_chat.index.clear_chat",
  "ai_welcome" => "channel_ai_chat.index.welcome", "ai_example_1" => "channel_ai_chat.index.example_1",
  "ai_example_2" => "channel_ai_chat.index.example_2", "ai_example_3" => "channel_ai_chat.index.example_3",
  "ai_placeholder" => "channel_ai_chat.index.placeholder", "ai_send" => "channel_ai_chat.index.send",
  "ai_empty_message" => "channel_ai_chat.errors.empty_message",
  "ai_thinking" => "js.channel_ai_chat.thinking", "ai_error" => "js.channel_ai_chat.error",
  "ai_failed_to_connect" => "js.channel_ai_chat.failed_to_connect", "ai_proposed_channels" => "js.channel_ai_chat.proposed_channels",
  "ai_create_selected" => "js.channel_ai_chat.create_selected", "ai_create_all" => "js.channel_ai_chat.create_all",
  "ai_new_templates" => "js.channel_ai_chat.new_templates", "ai_no_description" => "js.channel_ai_chat.no_description",
  "ai_threshold" => "js.channel_ai_chat.threshold", "ai_style" => "js.channel_ai_chat.style",
  "ai_language" => "js.channel_ai_chat.language", "ai_content_style" => "js.channel_ai_chat.content_style",
  "ai_relevance_threshold" => "js.channel_ai_chat.relevance_threshold",
  "ai_relevance_criteria" => "js.channel_ai_chat.relevance_criteria", "ai_expand" => "js.channel_ai_chat.expand",
  "ai_remove" => "js.channel_ai_chat.remove", "ai_none_selected" => "js.channel_ai_chat.none_selected",
  "ai_create_failed" => "js.channel_ai_chat.create_failed",

  # activity
  "activity_status_pending" => "activity_logs.statuses.pending", "activity_status_running" => "activity_logs.statuses.running",
  "activity_status_completed" => "activity_logs.statuses.completed", "activity_status_failed" => "activity_logs.statuses.failed",
  "activity_type_ingestion" => "activity_logs.types.ingestion", "activity_type_rating" => "activity_logs.types.rating",
  "activity_title" => "activity_logs.index.title", "activity_subtitle" => "activity_logs.index.subtitle",
  "activity_developer_logs" => "activity_logs.index.developer_logs", "activity_active_jobs" => "activity_logs.index.active_jobs",
  "activity_confirm_cleanup" => "activity_logs.index.confirm_cleanup", "activity_cleanup" => "activity_logs.index.cleanup",
  "activity_history" => "activity_logs.index.history", "activity_retry" => "activity_logs.index.retry",
  "activity_retry_rating" => "activity_logs.index.retry_rating", "activity_retry_ingestion" => "activity_logs.index.retry_ingestion",
  "activity_dev_logs" => "activity_logs.index.dev_logs", "activity_empty_title" => "activity_logs.index.empty_title",
  "activity_empty_hint" => "activity_logs.index.empty_hint",
  "activity_cancel_job" => "activity_logs.job_progress_card.cancel", "activity_confirm_cancel" => "activity_logs.job_progress_card.confirm_cancel",
  "dev_logs_title" => "activity_logs.all_dev_logs.title", "dev_logs_subtitle" => "activity_logs.all_dev_logs.subtitle",
  "dev_logs_heading" => "activity_logs.dev_logs.heading", "dev_logs_json_details" => "activity_logs.dev_logs.json_details",
  "dev_logs_view_details" => "activity_logs.dev_logs.view_details", "dev_logs_system_prompt" => "activity_logs.dev_logs.system_prompt",
  "dev_logs_user_prompt" => "activity_logs.dev_logs.user_prompt", "dev_logs_content_evaluated" => "activity_logs.dev_logs.content_evaluated",
  "dev_logs_score" => "activity_logs.dev_logs.score", "dev_logs_reason" => "activity_logs.dev_logs.reason",
  "dev_logs_raw_response" => "activity_logs.dev_logs.raw_response", "dev_logs_load_more" => "activity_logs.dev_logs.load_more",
  "dev_logs_empty_title" => "activity_logs.dev_logs.empty_title", "dev_logs_empty_hint" => "activity_logs.dev_logs.empty_hint",

  # user settings
  "settings_title" => "users.edit.title", "settings_language_label" => "users.edit.language.label",
  "settings_default_label" => "users.edit.default_label", "settings_save" => "users.edit.save",
  "settings_system_prompt_label" => "users.edit.system_prompt.label", "settings_system_prompt_intro" => "users.edit.system_prompt.intro_html",
  "settings_system_prompt_make_it_yours" => "users.edit.system_prompt.make_it_yours_html",
  "settings_event_link_label" => "users.edit.event_link.label", "settings_event_link_hint" => "users.edit.event_link.hint_html",
  "settings_naddr_link_label" => "users.edit.naddr_link.label", "settings_naddr_link_hint" => "users.edit.naddr_link.hint_html",
  "settings_profile_link_label" => "users.edit.profile_link.label", "settings_profile_link_hint" => "users.edit.profile_link.hint_html",
  "settings_rating_engine_label" => "users.edit.rating_engine.label", "settings_rating_engine_hint" => "users.edit.rating_engine.hint",
  "settings_engine_chat_label" => "users.edit.rating_engine.chat.label", "settings_engine_chat_badge" => "users.edit.rating_engine.chat.badge",
  "settings_engine_chat_hint" => "users.edit.rating_engine.chat.hint_html",
  "settings_engine_decision_label" => "users.edit.rating_engine.decision.label",
  "settings_engine_decision_badge" => "users.edit.rating_engine.decision.badge",
  "settings_engine_decision_hint" => "users.edit.rating_engine.decision.hint_html",
  "settings_writing_style_label" => "users.edit.writing_style.label", "settings_writing_style_hint" => "users.edit.writing_style.hint",
  "settings_writing_style_placeholder" => "users.edit.writing_style.placeholder",
  "templates_title" => "users.edit.templates.title", "templates_subtitle" => "users.edit.templates.subtitle",
  "templates_add_from_preset" => "users.edit.templates.add_from_preset", "templates_confirm_delete" => "users.edit.templates.confirm_delete",
  "templates_name" => "users.edit.templates.name", "templates_content" => "users.edit.templates.content",
  "templates_save" => "users.edit.templates.save", "templates_empty" => "users.edit.templates.empty",
  "templates_add_custom" => "users.edit.templates.add_custom", "templates_name_placeholder" => "users.edit.templates.name_placeholder",
  "templates_add" => "users.edit.templates.add",
  "search_index_title" => "users.edit.search_index.title", "search_index_subtitle" => "users.edit.search_index.subtitle",
  "search_index_status" => "users.edit.search_index.status_html", "search_index_rebuild" => "users.edit.search_index.rebuild",
  "search_index_confirm_rebuild" => "users.edit.search_index.confirm_rebuild",

  # API tokens
  "tokens_title" => "users.api_tokens.title", "tokens_intro" => "users.api_tokens.intro_html",
  "tokens_created" => "users.api_tokens.created_html", "tokens_new_token_label" => "users.api_tokens.new_token_label",
  "tokens_name_label" => "users.api_tokens.name_label", "tokens_name_placeholder" => "users.api_tokens.name_placeholder",
  "tokens_generate" => "users.api_tokens.generate", "tokens_created_column" => "users.api_tokens.columns.created",
  "tokens_last_used" => "users.api_tokens.columns.last_used", "tokens_never" => "users.api_tokens.never",
  "tokens_revoke" => "users.api_tokens.revoke", "tokens_confirm_revoke" => "users.api_tokens.confirm_revoke",
  "tokens_empty" => "users.api_tokens.empty", "tokens_name_required" => "api_tokens.create.name_required",
}.freeze

# Per-key rewrites applied to the raw YAML text before conversion.
TRANSFORMS = {
  # The web names the model; the API doesn't expose it, so drop that clause.
  "settings_engine_chat_hint" => ->(s) { s.sub(/,?\s*(?:to|a|posílá se do|posiela sa do)\s*<code>%\{model\}<\/code>/, "") },
  "settings_engine_decision_hint" => ->(s) { s.sub(/,?\s*(?:to|a|posílá se do|posiela sa do)\s*<code>%\{model\}<\/code>/, "") },
  "billing_self_host" => ->(s) { s.gsub("%{link}", "github.com/jooray/lievik") },
}.freeze

def deep_merge(a, b)
  a.merge(b) { |_, x, y| x.is_a?(Hash) && y.is_a?(Hash) ? deep_merge(x, y) : y }
end

def load_locale(lang)
  Dir[File.join(ROOT, "config/locales/**/#{lang}.yml")].sort.reduce({}) do |acc, file|
    data = YAML.safe_load_file(file, aliases: true) || {}
    deep_merge(acc, data.fetch(lang, {}))
  end
end

def dig(tree, path)
  path.split(".").reduce(tree) { |node, key| node.is_a?(Hash) ? node[key] : nil }
end

def xml_text(s)
  s = s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
  s = s.gsub("\\", "\\\\\\\\").gsub("'", "\\\\'").gsub("\"", "\\\\\"").gsub("\n", "\\n")
  s = "\\#{s}" if s.start_with?("@", "?")
  s
end

# Rails text → Android text. names: the placeholder order (from English).
def convert(text, names, html)
  s = text.dup
  if html
    s = s.gsub(/<[^>]+>/, "")
    s = CGI.unescapeHTML(s)
  end
  s = s.gsub(/%\{(\w+)\}/) do
    name = Regexp.last_match(1)
    index = names.index(name) or raise "placeholder %{#{name}} not in English: #{text}"
    "\u0001#{index + 1}$#{name == "count" ? "d" : "s"}\u0002"
  end
  formatted = s.include?("\u0001")
  s = s.gsub("%", "%%") if formatted
  s = xml_text(s)
  s = s.gsub("\u0001", "%").gsub("\u0002", "")
  [s, formatted || !s.include?("%")]
end

def placeholder_names(value)
  texts = value.is_a?(Hash) ? [value["other"], value["one"]].compact : [value]
  texts.flat_map { |t| t.scan(/%\{(\w+)\}/).flatten }.uniq
end

def write(path, entries)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, <<~XML)
    <?xml version="1.0" encoding="utf-8"?>
    <!-- Generated by android/tools/strings/generate.rb. Do not edit by hand. -->
    <resources>
    #{entries.join("\n")}
    </resources>
  XML
end

require "fileutils"

locales = LANGS.to_h { |lang| [lang, load_locale(lang)] }
english = locales["en"]
args_report = []

LANGS.each do |lang|
  dir = lang == "en" ? "values" : "values-#{lang}"
  entries = WEB.map do |name, path|
    raw = dig(locales[lang], path) or raise "#{lang}: missing #{path} (#{name})"
    en_raw = dig(english, path)
    transform = TRANSFORMS[name]
    if transform
      raw = raw.is_a?(Hash) ? raw.transform_values(&transform) : transform.call(raw)
      en_raw = en_raw.is_a?(Hash) ? en_raw.transform_values(&transform) : transform.call(en_raw)
    end
    html = path.end_with?("_html")
    names = placeholder_names(en_raw)
    args_report << "#{name}: #{names.join(", ")}" if lang == "en" && names.any?
    if raw.is_a?(Hash)
      items = QUANTITIES.fetch(lang).map do |q|
        text = raw[q] || raw["other"] or raise "#{lang}: #{path} lacks #{q}/other"
        converted, = convert(text, names, html)
        %(        <item quantity="#{q}">#{converted}</item>)
      end
      %(    <plurals name="#{name}">\n#{items.join("\n")}\n    </plurals>)
    else
      converted, formatted = convert(raw, names, html)
      attr = formatted ? "" : ' formatted="false"'
      %(    <string name="#{name}"#{attr}>#{converted}</string>)
    end
  end
  write(File.join(RES, dir, "strings_web.xml"), entries)
end

app = YAML.safe_load_file(File.join(__dir__, "app_strings.yml"))
LANGS.each do |lang|
  dir = lang == "en" ? "values" : "values-#{lang}"
  entries = app.map do |name, per_lang|
    raise "#{name} duplicates a web string" if WEB.key?(name)
    value = per_lang[lang] or raise "app_strings.yml: #{name} lacks #{lang}"
    if value.is_a?(Hash)
      items = QUANTITIES.fetch(lang).map do |q|
        text = value[q] || value["other"] or raise "#{name}/#{lang} lacks other"
        %(        <item quantity="#{q}">#{xml_text(text)}</item>)
      end
      %(    <plurals name="#{name}">\n#{items.join("\n")}\n    </plurals>)
    else
      %(    <string name="#{name}">#{xml_text(value)}</string>)
    end
  end
  write(File.join(RES, dir, "strings_app.xml"), entries)
end

puts "Generated #{WEB.size} web + #{app.size} app strings in #{LANGS.size} languages."
puts "Placeholder order (web strings):"
puts args_report.map { |l| "  #{l}" }
