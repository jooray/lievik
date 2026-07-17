# frozen_string_literal: true

class Source < ApplicationRecord
  attribute :settings, :json, default: -> { {} }

  belongs_to :user
  has_many :events, dependent: :destroy

  enum :source_type, { nostr: 0, manual: 1, rss: 2 }

  validates :identifier, presence: true
  validates :identifier, uniqueness: { scope: [:user_id, :source_type] }
  validates :distance, inclusion: { in: 0..10 }

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
end
