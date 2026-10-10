# frozen_string_literal: true

# Helpers for the app API request specs (spec/requests/api/v1).
module ApiHelpers
  include ActiveSupport::Testing::TimeHelpers

  def api_user(name = "user", digit = "1")
    user = User.create!(npub: "npub1#{name}", pubkey_hex: digit * 64, display_name: name)
    user.sources.create!(source_type: :manual, identifier: "manual", name: "Manual entries", distance: 1)
    user
  end

  def api_token_for(user, name: "spec")
    ApiToken.generate(user, name: name).plain_token
  end

  def api_headers(token, locale: nil)
    headers = { "Authorization" => "Bearer #{token}", "Accept" => "application/json" }
    headers["Accept-Language"] = locale if locale
    headers
  end

  # Request helpers that send JSON with the bearer token.
  %i[get post patch delete].each do |verb|
    define_method(:"api_#{verb}") do |path, token, params: nil, locale: nil|
      if verb == :get
        public_send(verb, path, params: params, headers: api_headers(token, locale: locale))
      else
        public_send(verb, path, params: params, headers: api_headers(token, locale: locale), as: :json)
      end
    end
  end

  def json
    response.parsed_body
  end

  # The server-sent events of a streamed response as [[event, data], ...].
  def sse_events(body = response.body)
    body.split("\n\n").filter_map do |block|
      name = block[/^event: (.+)$/, 1]
      data = block[/^data: (.*)$/m, 1]
      [ name, JSON.parse(data) ] if name
    end
  end

  # Rails.cache is a null store in tests; the challenge store, rate limits and
  # the billing ledger need a real one.
  def use_memory_cache
    @api_previous_cache ||= Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end
end

RSpec.configure do |config|
  config.include ApiHelpers, type: :request
  config.after do
    if @api_previous_cache
      Rails.cache = @api_previous_cache
      @api_previous_cache = nil
    end
  end
end
