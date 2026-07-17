# frozen_string_literal: true

class User < ApplicationRecord
  attribute :settings, :json, default: -> { {} }
  attribute :content_templates, :json, default: -> { [] }

  has_many :sources, dependent: :destroy
  has_many :channels, dependent: :destroy
  has_many :events, through: :sources
  has_many :activity_logs, dependent: :destroy
  has_many :channel_contents, dependent: :destroy
  has_many :api_tokens, dependent: :destroy

  validates :npub, presence: true, uniqueness: true
  validates :pubkey_hex, presence: true, uniqueness: true

  def display_name_or_npub
    display_name.presence || username.presence || npub.truncate(20)
  end

  DEFAULT_EVENT_LINK_TEMPLATE = "https://yakihonne.com/note/{eventid}"
  DEFAULT_NADDR_LINK_TEMPLATE = "https://yakihonne.com/article/{naddr}"
  DEFAULT_PROFILE_LINK_TEMPLATE = "https://yakihonne.com/profile/{npub}"

  def event_link_template
    settings&.dig("event_link_template").presence || DEFAULT_EVENT_LINK_TEMPLATE
  end

  def event_link_template=(value)
    self.settings = (settings || {}).merge("event_link_template" => value)
  end

  def naddr_link_template
    settings&.dig("naddr_link_template").presence || DEFAULT_NADDR_LINK_TEMPLATE
  end

  def naddr_link_template=(value)
    self.settings = (settings || {}).merge("naddr_link_template" => value)
  end

  def profile_link_template
    settings&.dig("profile_link_template").presence || DEFAULT_PROFILE_LINK_TEMPLATE
  end

  def profile_link_template=(value)
    self.settings = (settings || {}).merge("profile_link_template" => value)
  end

  def profile_url(npub)
    profile_link_template.gsub("{npub}", npub)
  end

  DEFAULT_SYSTEM_PROMPT = <<~PROMPT
    You are assisting a Lievik user in curating high-quality content from Nostr and RSS for marketing channels.

    Lievik ingests short text notes (kind 1), reposts (kind 6), and long-form content (kind 30023) from selected Nostr accounts (sources: user's own npub + other npubs), plus RSS feeds. AI rates relevance (0-100) for each marketing channel (newsletters, chat groups, social) based on channel criteria.
  PROMPT

  def system_prompt
    super.presence || DEFAULT_SYSTEM_PROMPT
  end

  # Content templates for channel formatting instructions
  # Returns array of {name: "Template Name", template: "Template content..."}
  def content_templates_list
    content_templates.presence || []
  end

  def add_content_template(name:, template:)
    templates = content_templates_list
    templates << { "name" => name, "template" => template }
    update!(content_templates: templates)
  end

  def update_content_template(index, name:, template:)
    templates = content_templates_list
    return false if index < 0 || index >= templates.length

    templates[index] = { "name" => name, "template" => template }
    update!(content_templates: templates)
  end

  def delete_content_template(index)
    templates = content_templates_list
    return false if index < 0 || index >= templates.length

    templates.delete_at(index)
    update!(content_templates: templates)
  end

  DEFAULT_CONTENT_TEMPLATES = [
    {
      "name" => "Newsletter",
      "template" => <<~TEMPLATE
        # Newsletter Format

        ## Output Format
        Email newsletter section with a brief introduction, 3-5 bullet points highlighting key content, and a call-to-action.

        ## Writing Style
        Professional but friendly. Use "you" to address the reader directly. Keep sentences concise.

        ## Structure
        - Opening hook (1-2 sentences)
        - Main content highlights as bullet points
        - Brief commentary connecting the pieces
        - Clear call-to-action at the end

        ## Formatting Rules
        - Use markdown for structure
        - Include source links inline
        - Keep total length under 500 words
      TEMPLATE
    },
    {
      "name" => "Signal/Chat Group",
      "template" => <<~TEMPLATE
        # Chat Group Format

        ## Output Format
        Short, conversational message suitable for Signal, Telegram, or similar group chats.

        ## Writing Style
        Casual and direct. Use plain language. Okay to use common abbreviations.

        ## Structure
        - Brief intro (1 sentence max)
        - Key point or announcement
        - Relevant link(s)
        - Optional: emoji for tone

        ## Formatting Rules
        - Keep under 280 characters if possible
        - One link per message preferred
        - No markdown headers, just plain text
      TEMPLATE
    },
    {
      "name" => "Social Media Post",
      "template" => <<~TEMPLATE
        # Social Post Format

        ## Output Format
        Engaging social media post optimized for engagement and sharing.

        ## Writing Style
        Punchy and attention-grabbing. Start with a hook. Use active voice.

        ## Structure
        - Hook or question to grab attention
        - Core insight or value proposition
        - Link to full content
        - Relevant hashtags (if appropriate)

        ## Formatting Rules
        - Under 280 characters for Twitter/X
        - Can be longer for other platforms
        - Include one clear call-to-action
      TEMPLATE
    }
  ].freeze

  def self.default_content_templates
    DEFAULT_CONTENT_TEMPLATES
  end
end
