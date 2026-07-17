# frozen_string_literal: true

class ChannelContentEvent < ApplicationRecord
  belongs_to :channel_content
  belongs_to :event

  validates :event_id, uniqueness: { scope: :channel_content_id }
end
