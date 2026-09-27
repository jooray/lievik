# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Interface language", type: :request do
  it "follows Accept-Language for a first-time visitor" do
    get nostr_login_path, headers: { "Accept-Language" => "cs-CZ,cs;q=0.9,en;q=0.8" }

    expect(response.body).to include('lang="cs"')
  end

  it "defaults to English for unsupported languages" do
    get nostr_login_path, headers: { "Accept-Language" => "de-DE,de;q=0.9" }

    expect(response.body).to include('lang="en"')
  end

  it "remembers ?locale= in a cookie" do
    get nostr_login_path, params: { locale: "es" }
    expect(response.body).to include('lang="es"')

    get nostr_login_path, headers: { "Accept-Language" => "sk" }
    expect(response.body).to include('lang="es"')
  end

  it "ignores unknown ?locale= values" do
    get nostr_login_path, params: { locale: "xx" }

    expect(response.body).to include('lang="en"')
  end

  it "serves the localized landing pages" do
    %w[en sk cs es].each do |locale|
      get localized_landing_path(locale: locale)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(lang="#{locale}"))
    end
  end

  context "signed in" do
    let!(:user) { User.create!(npub: "npub1localeui", pubkey_hex: "d" * 64, display_name: "Locale") }

    before { allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user) }

    it "saves the language from the settings form and uses it over Accept-Language" do
      patch user_path, params: { user: { locale: "sk" } }
      expect(user.reload.locale).to eq("sk")

      get edit_user_path, headers: { "Accept-Language" => "es" }
      expect(response.body).to include('lang="sk"')
    end

    it "stores a ?locale= switch on the user" do
      get dashboard_path, params: { locale: "cs" }

      expect(user.reload.locale).to eq("cs")
    end

    it "rejects unknown languages in settings" do
      user.update!(locale: "sk")
      patch user_path, params: { user: { locale: "klingon" } }

      expect(user.reload.locale).to be_nil
    end
  end
end
