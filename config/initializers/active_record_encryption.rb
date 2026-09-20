# frozen_string_literal: true

# Keys for ActiveRecord::Encryption, backing `encrypts :temp_privkey, :secret`
# on NostrAuthSession — the ephemeral NIP-46 client private key and the
# one-time connect secret. Both are short-lived (the approval window is 5
# minutes) but they are exactly the material that authenticates a login, and
# they used to sit in the database as plain columns.
#
# Key sources, in priority order:
#
#   1. Rails encrypted credentials — bin/rails credentials:edit
#        active_record_encryption:
#          primary_key: ...
#          deterministic_key: ...
#          key_derivation_salt: ...
#
#   2. Plain environment variables, since production loads its secrets from
#      ~/apps/lievik/.env via systemd's EnvironmentFile rather than
#      config/master.key (the same pattern as VENICE_API_KEY):
#        ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY
#        ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
#        ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
#
#   3. Derived from secret_key_base.
#
# Step 3 exists because of the failure mode it removes. Without it, deploying
# `encrypts` before the env vars are in place makes every single login raise at
# runtime — a total login outage, caused by the very commit meant to harden
# login. secret_key_base is already mandatory in production, so a derived key
# is always available. It is a real key (HKDF via KeyGenerator), not a
# placeholder; the only thing it gives up is the ability to rotate these keys
# independently of secret_key_base, which is why the explicit sources win.
#
# Generate an explicit set with:
#   ruby -rsecurerandom -e '3.times { puts SecureRandom.alphanumeric(32) }'
credentials = Rails.application.credentials.active_record_encryption || {}

derived = lambda do |purpose|
  secret_key_base = Rails.application.secret_key_base
  ActiveSupport::KeyGenerator.new(secret_key_base, hash_digest_class: OpenSSL::Digest::SHA256)
                             .generate_key("lievik/active_record_encryption/#{purpose}", 32)
                             .unpack1("H*")
end

Rails.application.config.active_record.encryption.primary_key =
  credentials[:primary_key].presence ||
  ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"].presence ||
  derived.call("primary_key")

Rails.application.config.active_record.encryption.deterministic_key =
  credentials[:deterministic_key].presence ||
  ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"].presence ||
  derived.call("deterministic_key")

Rails.application.config.active_record.encryption.key_derivation_salt =
  credentials[:key_derivation_salt].presence ||
  ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"].presence ||
  derived.call("key_derivation_salt")

# Rows written before this initializer existed are plaintext. This lets the app
# keep reading them instead of raising. Auth sessions expire within minutes and
# `NostrAuthSession.cleanup_expired!` deletes them, so the plaintext rows drain
# on their own within one approval window of the deploy — but a login that is
# mid-flight across the deploy would otherwise break, which is precisely the
# moment a user is watching.
Rails.application.config.active_record.encryption.support_unencrypted_data = true
