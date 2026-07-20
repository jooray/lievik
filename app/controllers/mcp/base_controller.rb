# frozen_string_literal: true

module Mcp
  class BaseController < ActionController::API
    # Token guessing and runaway agent loops both look like a flood of requests
    # from one IP, so cap it. Legitimate agent usage is well under this.
    rate_limit to: 120, within: 1.minute, name: "mcp-requests", with: :mcp_rate_limit_exceeded

    before_action :authenticate_api_token!

    attr_reader :current_user

    private

    def authenticate_api_token!
      token = bearer_token
      @current_user = ApiToken.authenticate(token) if token.present?

      return if @current_user

      Rails.logger.warn(
        "[MCP] auth failure from #{request.remote_ip} " \
        "(token #{token.present? ? 'present but invalid' : 'missing'})"
      )
      render json: { error: "unauthorized" }, status: :unauthorized
    end

    def mcp_rate_limit_exceeded
      response.set_header("Retry-After", "60")
      render json: { error: "rate_limited" }, status: :too_many_requests
    end

    def bearer_token
      header = request.headers["Authorization"].to_s
      return nil unless header.start_with?("Bearer ")

      header.sub(/\ABearer\s+/, "").strip
    end
  end
end
