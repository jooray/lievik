# frozen_string_literal: true

# The app API (docs/API_V1.md):
# * GET /api/v1/sync pages through rows changed since a timestamp, keyset on
#   (updated_at, id) within one user's sources / channels.
# * A NIP-46 login started by the app has no cookie session to bind to, so the
#   creator gets a secret poll token; only its SHA-256 digest is stored.
# Plain column indexes and a nullable string: portable to SQLite and MariaDB.
class AddAppApiSyncIndexesAndPollToken < ActiveRecord::Migration[8.1]
  def change
    add_index :events, [ :source_id, :updated_at, :id ], name: "index_events_on_source_updated_id"
    add_index :channel_events, [ :channel_id, :updated_at, :id ], name: "index_channel_events_on_channel_updated_id"
    add_column :nostr_auth_sessions, :poll_token_digest, :string
  end
end
