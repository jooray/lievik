# frozen_string_literal: true

class LinkedContent < ApplicationRecord
  attribute :metadata, :json, default: -> { {} }

  has_many :event_links, dependent: :destroy
  has_many :events, through: :event_links

  validates :url, presence: true, uniqueness: true

  scope :unfetched, -> { where(fetched_at: nil) }
  scope :fetched, -> { where.not(fetched_at: nil) }
end
