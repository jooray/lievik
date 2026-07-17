# frozen_string_literal: true

class Channel < ApplicationRecord
  attribute :settings, :json, default: -> { {} }

  belongs_to :user
  has_many :channel_events, dependent: :destroy
  has_many :events, through: :channel_events
  has_many :channel_contents, dependent: :destroy

  validates :name, presence: true
  validates :language, presence: true

  after_initialize :set_default_settings, if: :new_record?

  def self.default_settings
    {
      "relevance_threshold" => 50,
      "channel_type" => "pull",
      "humanize_output" => true
    }
  end

  def self.default_prompt_template
    <<~TEMPLATE
      # Channel Purpose
      *Describe what this channel is for, e.g., "Newsletter for my privacy course students"*

      ## Target Audience
      *Who receives content from this channel? E.g., "People learning about digital privacy and security"*

      ## Relevance Criteria

      ### Highly relevant, perfect fit (Score 80-100)
      - Content directly about *your main topic*
      - Announcements and updates relevant to the audience
      - Educational content that helps them

      ### Moderately relevant, could be useful (Score 50-79)
      - Related industry news
      - Commentary on relevant trends
      - Content that might interest the audience

      ### Low relevance, tangentially related (Score 20-49)
      - Tangentially related topics
      - General news without direct relevance

      ### Not relevant, should be excluded (Score 0-19)
      - Off-topic content
      - Personal posts unrelated to the channel
      - Spam or promotional content
    TEMPLATE
  end

  def self.default_content_prompt_template
    <<~TEMPLATE
      # Content Generation Instructions

      ## Output Format
      *E.g., "Newsletter section with introduction, bullet points, and call-to-action"*

      ## Writing Style
      *E.g., "Professional but approachable, use second person ('you'), avoid jargon"*

      ## Structure
      - Start with a hook or key insight
      - Summarize the main points
      - End with an actionable takeaway

      ## Formatting Rules
      - Use markdown headers for sections
      - Keep paragraphs concise (2-3 sentences)
      - Include relevant links where appropriate
    TEMPLATE
  end

  def relevance_threshold
    settings&.dig("relevance_threshold") || 50
  end

  def humanize_output?
    settings&.dig("humanize_output") != false
  end

  def relevant_events
    channel_events.above_threshold(relevance_threshold).by_relevance
  end

  def rate_new_events!
    RateEventsJob.perform_later(id)
  end

  def effective_content_language
    content_language.presence || language
  end

  private

  def set_default_settings
    self.settings ||= self.class.default_settings
  end
end
