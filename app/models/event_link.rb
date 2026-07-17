# frozen_string_literal: true

class EventLink < ApplicationRecord
  belongs_to :event
  belongs_to :linked_content

  enum :link_type, { url: 0, nostr_event: 1, nostr_profile: 2 }
end
