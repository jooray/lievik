# frozen_string_literal: true

# Bearer-token authentication shared by the MCP endpoint and the app API.
# Tokens are ApiToken records (created at /user/edit or by an app sign-in).
module ApiTokenAuthentication
  extend ActiveSupport::Concern

  private

  def bearer_token
    header = request.headers["Authorization"].to_s
    return nil unless header.start_with?("Bearer ")

    header.sub(/\ABearer\s+/, "").strip
  end

  # The ApiToken for this request, or nil (missing, unknown or expired).
  def authenticate_bearer_token
    token = bearer_token
    ApiToken.authenticate_token(token) if token.present?
  end

  # A stable per-token rate-limit key that is not the secret itself; falls
  # back to the IP for requests without a token.
  def rate_limit_key
    token = bearer_token
    token.present? ? "token:#{ApiToken.digest_for(token)}" : "ip:#{request.remote_ip}"
  end
end
