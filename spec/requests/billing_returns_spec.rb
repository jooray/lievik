# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Billing return to the app", type: :request do
  it "hands a signed-out browser back to the app instead of asking it to sign in" do
    get "/billing/app_return", headers: { "Accept-Language" => "sk" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('href="lievik://billing"')
    expect(response.body).to include('window.location.replace("lievik://billing")')
    expect(response.body).to include("Späť do Lievika")
  end
end
