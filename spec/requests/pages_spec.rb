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

  describe "installing on an Android device" do
    let(:android_ua) { "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36" }
    let(:iphone_ua) { "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1" }

    def install_section
      response.body[/<section class="how install[^>]*>.*?<\/section>/m]
    end

    it "puts the native app first with Zapstore as the main button, and the web app second" do
      get localized_landing_path(locale: :en), headers: { "User-Agent" => android_ua }

      section = install_section
      expect(section).to include("install-android", "Recommended for Android", "The web app works too")
      expect(section.index("install-native")).to be < section.index("install-web")
      expect(section).to include(%(href="#{ApplicationHelper::ANDROID_APP_LINKS[:zapstore]}" rel="noopener noreferrer" class="button"))
      expect(section).not_to include("Add to Home Screen")
      expect(response.headers["Vary"]).to include("User-Agent")
    end

    it "keeps the web app first with the iOS how-to everywhere else" do
      get localized_landing_path(locale: :en), headers: { "User-Agent" => iphone_ua }

      section = install_section
      expect(section).not_to include("install-android", "Recommended for Android")
      expect(section.index("install-web")).to be < section.index("install-native")
      expect(section).to include("Add to Home Screen")
      expect(section).not_to include('class="button"')
    end
  end
end
