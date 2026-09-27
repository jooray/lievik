class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  around_action :switch_locale
  before_action :authenticate_user!

  helper_method :current_user, :user_signed_in?

  private

  LOCALE_COOKIE = :locale

  # Resolution order: explicit ?locale= (also remembered), the signed-in
  # user's saved choice, the cookie a visitor got from the landing page
  # switcher, then Accept-Language, then English.
  def switch_locale(&action)
    locale = requested_locale || current_user&.locale || supported_locale(cookies[LOCALE_COOKIE]) ||
             accept_language_locale || I18n.default_locale
    I18n.with_locale(locale, &action)
  end

  def requested_locale
    locale = supported_locale(params[:locale])
    return unless locale

    remember_locale(locale)
    locale
  end

  def remember_locale(locale)
    cookies[LOCALE_COOKIE] = { value: locale.to_s, expires: 1.year, same_site: :lax }
    current_user.update(locale: locale) if current_user && current_user.locale != locale.to_s
  end

  def supported_locale(value)
    value = value.to_s.downcase
    I18n.available_locales.find { |l| l.to_s == value }
  end

  def accept_language_locale
    request.headers["Accept-Language"].to_s.split(",").each do |part|
      tag = part.split(";").first.to_s.strip.downcase
      locale = supported_locale(tag.split("-").first)
      return locale if locale
    end
    nil
  end

  def current_user
    @current_user ||= User.find_by(id: session[:user_id]) if session[:user_id]
  end

  def user_signed_in?
    current_user.present?
  end

  def authenticate_user!
    unless user_signed_in?
      redirect_to nostr_login_path, alert: t("auth.sign_in_required")
    end
  end
end
