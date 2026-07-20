# frozen_string_literal: true

# Build identity for the PWA update check.
#
# The browser caches the JS/CSS bundle, so without a version signal an installed
# PWA happily runs last week's code forever. Every page embeds this value and
# polls /version.json; when the two diverge the client reloads itself.
#
# Resolution order, most to least meaningful:
#   1. APP_VERSION env var — set it explicitly if you want full control.
#   2. The compiled asset manifest digest — changes exactly when assets change.
#   3. The deployed git SHA — production deploys are a git checkout.
#   4. Boot time — development fallback.
module Lievik
  BUILD_VERSION = begin
    explicit = ENV["APP_VERSION"].presence

    manifest = Rails.root.join("public/assets/.manifest.json")
    manifest_digest = Digest::SHA256.file(manifest).hexdigest.first(12) if manifest.exist?

    git_sha = begin
      sha = `git -C #{Rails.root.to_s.shellescape} rev-parse --short HEAD 2>/dev/null`.strip
      sha.presence
    rescue StandardError
      nil
    end

    explicit || manifest_digest || git_sha || Time.current.to_i.to_s
  end
end
