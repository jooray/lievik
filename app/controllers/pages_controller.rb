# frozen_string_literal: true

class PagesController < ApplicationController
  skip_before_action :authenticate_user!, only: :landing

  # Public landing page at "/". Signed-in users go straight to their dashboard;
  # everyone else sees the marketing page with a "Launch app" link into auth.
  def landing
    return redirect_to dashboard_path if user_signed_in?

    render layout: false
  end
end
