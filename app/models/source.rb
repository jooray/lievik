# frozen_string_literal: true

class Source < ApplicationRecord
  attribute :settings, :json, default: -> { {} }

  belongs_to :user
  has_many :events, dependent: :destroy

  enum :source_type, { nostr: 0, manual: 1, rss: 2 }

  # A pasted npub often carries surrounding whitespace, which otherwise defeats
  # both the validation below and the ingestion service's prefix check.
  before_validation :normalize_identifier

  validates :identifier, presence: true
  validates :identifier, uniqueness: { scope: [:user_id, :source_type] }
  validates :distance, inclusion: { in: 0..10 }
  validate :nostr_identifier_is_decodable, if: :nostr?

  # virtual accessors for settings
  def settings_include_replies
    settings["include_replies"]
  end

  def settings_include_replies=(value)
    self.settings["include_replies"] = ActiveModel::Type::Boolean.new.cast(value)
  end

  def settings_include_reposts
    settings["include_reposts"]
  end

  def settings_include_reposts=(value)
    self.settings["include_reposts"] = ActiveModel::Type::Boolean.new.cast(value)
  end

  def settings_import_days
    settings["import_days"]
  end

  def settings_import_days=(value)
    self.settings["import_days"] = value.to_i
  end

  # Default settings for new sources
  after_initialize :set_default_settings, if: :new_record?

  def self.default_settings
    {
      "include_replies" => false,
      "include_reposts" => true,
      "import_days" => 30
    }
  end

  private

  def set_default_settings
    self.settings ||= self.class.default_settings
  end

  def normalize_identifier
    self.identifier = identifier.strip if identifier.is_a?(String)
  end

  # A nostr source is only usable if its identifier actually decodes to a
  # pubkey. Storing an undecodable one just breaks that source's recurring
  # ingestion for good, so reject it up front.
  def nostr_identifier_is_decodable
    return if identifier.blank?

    value = identifier.to_s.strip
    return if Nostr::KeyConverter.valid_hex_pubkey?(value)
    return if Nostr::KeyConverter.valid_npub?(value)

    errors.add(:identifier, "must be a valid npub or 64-character hex pubkey")
  end
end
