# frozen_string_literal: true

# Fetching a kind:0 profile talks to every configured relay in sequence and can
# take seconds. That must never happen inside a web request, so both login and
# the "refresh profile" button go through this job.
class RefreshUserProfileJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    profile = Nostr::ProfileFetcher.new.fetch(user.pubkey_hex)
    unless profile
      Rails.logger.info("No profile found on relays for user #{user_id}")
      return
    end

    user.update!(
      display_name: profile[:display_name],
      username: profile[:username],
      about: profile[:about],
      picture_url: profile[:picture]
    )
  end
end
