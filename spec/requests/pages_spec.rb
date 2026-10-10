# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Landing page", type: :request do
  describe "GET /" do
    it "renders the public landing page for logged-out visitors" do
      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nostr-first content curation")
      # Launch button points at the auth entry point
      expect(response.body).to include('href="/auth/nostr"')
    end

    it "redirects signed-in visitors to their dashboard" do
      user = User.create!(npub: "npub1landing", pubkey_hex: "a" * 64, display_name: "landing user")
      allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)

      get root_path

      expect(response).to redirect_to(dashboard_path)
    end
  end

  describe "GET /dashboard" do
    it "redirects logged-out visitors to the login page" do
      get dashboard_path

      expect(response).to redirect_to(nostr_login_path)
    end
  end

  describe "pricing on the landing page" do
    it "lists Lievik, the bundle with what it saves, and self-hosting" do
      get root_path, headers: { "Accept-Language" => "en" }

      expect(response.body).to include('href="#pricing"', 'id="pricing"')
      expect(response.body).to include("15,000 sats", "25,000 sats", "35,000")
      expect(response.body).to include("https://nalgorithm.cypherpunk.today", "https://emanator.cypherpunk.today")
      expect(response.body).to include("github.com/jooray/lievik")
    end
  end

  describe "installing on the landing page" do
    it "presents the web app as installable everywhere and the Android app as optional, in every locale" do
      I18n.available_locales.each do |locale|
        get localized_landing_path(locale: locale)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('id="install"', "Safari", *ApplicationHelper::ANDROID_APP_LINKS.values)
      end
    end
  end
end
